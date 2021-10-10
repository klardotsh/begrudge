// This source code is part of the begrudge project, released under the CC0-1.0
// dedication found in the COPYING file in the root directory of this source
// tree, or at https://creativecommons.org/publicdomain/zero/1.0/

const std = @import("std");
const eql = std.mem.eql;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const trimLeft = std.mem.trimLeft;

const ESCAPE_1 = '\u{001b}';
const ESCAPE_2 = '[';
const UNESCAPE = 'm';
const COMBO = ';';
// we trim leading 0's, so RESET is just an empty instruction, see
// parse_instruction()
const BOLD = '1';
const UNDERSCORE = '4';
const BLINK = '5'; // cursed tag, truly
const HIDDEN = '8';
const FG_FAMILY = '3';
const BRIGHT_FG_FAMILY = '9';
const BG_FAMILY = '4';

// TODO allow changing or removing the begrudge- prefix?
const SPAN_OPEN = "<span class='begrudge-{s}'>";
const SPAN_CLOSE = "</span>";
const SPAN_CLASS_BOLD = "bold";
const SPAN_CLASS_UNDERSCORE = "underscore";
const SPAN_CLASS_BLINK = "blink";
const SPAN_CLASS_HIDDEN = "hidden";
const LONGEST_SPAN_CLASS_NAME = std.mem.max(usize, &.{
    SPAN_CLASS_BOLD.len,
    SPAN_CLASS_UNDERSCORE.len,
    SPAN_CLASS_BLINK.len,
    SPAN_CLASS_HIDDEN.len,
});

// this is *not* the fancy-shmancy and generally considered to be
// much-more-correct https://vt100.net/emu/dec_ansi_parser state machine, but
// rather an internal representation of what spans are currently open. we'll
// classify our supported escapess into a few categories, of which only one of
// each category can be on at a given time. when we see a RESET, that's easy:
// just close all open spans and call it a day. however, there's no guarantee
// we'll see a RESET between two escapes of the same category (perhaps we
// turned on BOLD and BG_2 but want to flip between FG_1 and FG_4). while the
// "correct" (and most tag-efficient) thing to do is to track the order that
// spans were opened and close only as many as necessary to unroll back to the
// FG_1, then open an FG_4 and re-open all the other spans, the *simple* thing
// to do is to simply close all spans when we change escapes within a category,
// and reopen all new ones.
//
// this state struct tracks enough... state... to enable the above behavior
const State = struct {
    // while zig exposes the default values of a struct (and we even use that
    // functionality later on), it's exposed as an array of StructFields, and
    // for random lookups, O(1) is of course nice. so we'll just store this for
    // when we need to look up by field name later.
    const default_state = .{
        .bold = false,
        .underscore = false,
        .blink = false,
        .hidden = false,
        .fg = null,
        .bg = null,
    };

    bold: bool = default_state.bold,
    underscore: bool = default_state.underscore,
    blink: bool = default_state.blink,
    hidden: bool = default_state.hidden,
    fg: ?u8 = default_state.fg,
    bg: ?u8 = default_state.bg,

    pub fn num_differing_fields(self: *@This()) u8 {
        var differing_fields: u8 = 0;
        inline for (std.meta.fields(@This())) |field| {
            if (@field(self, field.name) != @field(default_state, field.name)) {
                differing_fields += 1;
            }
        }
        return differing_fields;
        // if (self.bold != default_state.bold) differing_fields += 1;
        // if (self.underscore != default_state.underscore) differing_fields += 1;
        // if (self.blink != default_state.blink) differing_fields += 1;
        // if (self.hidden != default_state.hidden) differing_fields += 1;
        // if (self.fg) |fg| differing_fields += 1;
        // if (self.bg) |bg| differing_fields += 1;
    }

    pub fn write_all_open_spans(self: *@This(), output: anytype, color_class_buf: []u8) !void {
        var span_buf: [SPAN_OPEN.len + LONGEST_SPAN_CLASS_NAME]u8 = undefined;

        inline for (std.meta.fields(@This())) |field| {
            if (@field(self, field.name) != @field(default_state, field.name)) {
                var class_name = field.name;

                // the type system (rightfully) gets real cranky with these
                // hacks on nullable fields, so fg and bg need handled (1)
                // separately from everything else, and (2) separately from
                // *each other*
                if (eql(u8, field.name, "fg")) {
                    if (self.fg) |fg| {
                        class_name = try color_class_name(field.name, fg, color_class_buf);
                    }
                }
                if (eql(u8, field.name, "bg")) {
                    if (self.bg) |bg| {
                        class_name = try color_class_name(field.name, bg, color_class_buf);
                    }
                }
                const tag = try std.fmt.bufPrint(span_buf[0..], SPAN_OPEN, .{class_name});
                try output.writeAll(tag);
            }
        }
    }

    pub fn write_close_spans(self: *@This(), output: anytype, count: u8) !void {
        var close_idx: u8 = 0;
        while (close_idx < count) {
            try output.writeAll(SPAN_CLOSE);
            close_idx += 1;
        }
    }

    pub const OutputInstruction = union(enum) {
        /// some operations only require opening a single new tag (which
        /// doesn't conflict with any others currently open), this represents
        /// the new class name to open a span for
        Incremental: []const u8,

        /// for safety's sake, all other cases currently require a full
        /// teardown and rebuild of the tag stack. since the number of
        /// differing fields may have changed as part of the mutation, this u8
        /// tracks how many differing fields were detected before applying the
        /// mutation
        Rebuild: u8,
    };

    pub fn mutate(self: *@This(), mutation: Mutation, color_class_buf: []u8) !?OutputInstruction {
        const differing_fields = self.num_differing_fields();
        return switch (mutation) {
            .Reset => blk: {
                if (differing_fields == 0) break :blk null;
                inline for (std.meta.fields(@This())) |field| {
                    @field(self, field.name) = field.default_value.?;
                }
                break :blk OutputInstruction{ .Rebuild = differing_fields };
            },
            .BoldEnable => mutation_simple_enable(self, SPAN_CLASS_BOLD),
            .UnderscoreEnable => mutation_simple_enable(self, SPAN_CLASS_UNDERSCORE),
            .BlinkEnable => mutation_simple_enable(self, SPAN_CLASS_BLINK),
            .HiddenEnable => mutation_simple_enable(self, SPAN_CLASS_HIDDEN),
            .Foreground => |color_idx| try mutation_color_enable(self, "fg", color_idx, differing_fields, color_class_buf),
            .Background => |color_idx| try mutation_color_enable(self, "bg", color_idx, differing_fields, color_class_buf),
        };
    }

    fn mutation_simple_enable(self: *@This(), comptime field: []const u8) ?OutputInstruction {
        if (@field(self, field)) {
            return null;
        }

        @field(self, field) = true;
        return OutputInstruction{ .Incremental = field };
    }

    fn mutation_color_enable(
        self: *@This(),
        comptime field: []const u8,
        color: u8,
        differing_fields: u8,
        color_class_buf: []u8,
    ) !?OutputInstruction {
        const old_color = @field(self, field);
        if (color == old_color) {
            return null;
        }

        @field(self, field) = color;
        const class_name = try color_class_name(field, color, color_class_buf);

        if (old_color) |_| {
            return OutputInstruction{ .Rebuild = differing_fields };
        }
        return OutputInstruction{ .Incremental = class_name };
    }

    fn color_class_name(comptime field: []const u8, color: u8, color_class_buf: []u8) ![]const u8 {
        return try std.fmt.bufPrint(color_class_buf, "{s}-{d}", .{ field, color });
    }

    test "State.mutate::reset_everything" {
        var color_class_buf: [5]u8 = undefined;
        var state = State{
            .bold = true,
            .underscore = true,
            .blink = true,
            .hidden = true,
            .fg = 1,
            .bg = 8,
        };
        const expected_state = State{};
        const result = try state.mutate(Mutation{ .Reset = {} }, color_class_buf[0..]);
        try expectEqual(expected_state, state);
        try expectEqual(State.OutputInstruction{ .Rebuild = 6 }, result.?);
    }

    test "State.mutate::useless_resets_ignored" {
        var color_class_buf: [5]u8 = undefined;
        var state = State{};
        try expect(null == try state.mutate(Mutation{ .Reset = {} }, color_class_buf[0..]));
    }

    test "State.mutate::can_enable_bold" {
        var color_class_buf: [5]u8 = undefined;
        var state = State{};
        var expected_state = State{ .bold = true };
        var mutation = Mutation{ .BoldEnable = {} };

        const result = try state.mutate(mutation, color_class_buf[0..]);
        try expectEqual(expected_state, state);
        try expectEqual(State.OutputInstruction{ .Incremental = "bold" }, result.?);
    }

    test "State.mutate::can_enable_underscore" {
        var color_class_buf: [5]u8 = undefined;
        var state = State{};
        var expected_state = State{ .underscore = true };
        var mutation = Mutation{ .UnderscoreEnable = {} };

        const result = try state.mutate(mutation, color_class_buf[0..]);
        try expectEqual(expected_state, state);
        try expectEqual(State.OutputInstruction{ .Incremental = "underscore" }, result.?);
    }

    test "State.mutate::can_enable_blink" {
        var color_class_buf: [5]u8 = undefined;
        var state = State{};
        var expected_state = State{ .blink = true };
        var mutation = Mutation{ .BlinkEnable = {} };

        const result = try state.mutate(mutation, color_class_buf[0..]);
        try expectEqual(expected_state, state);
        try expectEqual(State.OutputInstruction{ .Incremental = "blink" }, result.?);
    }

    test "State.mutate::can_enable_hidden" {
        var color_class_buf: [5]u8 = undefined;
        var state = State{};
        var expected_state = State{ .hidden = true };
        var mutation = Mutation{ .HiddenEnable = {} };

        const result = try state.mutate(mutation, color_class_buf[0..]);
        try expectEqual(expected_state, state);
        try expectEqual(State.OutputInstruction{ .Incremental = "hidden" }, result.?);
    }

    test "State.mutate::can_enable_second_simple_toggle_without_closing_others" {
        var color_class_buf: [5]u8 = undefined;
        var state = State{ .bold = true };
        var expected_state = State{ .bold = true, .hidden = true };
        var mutation = Mutation{ .HiddenEnable = {} };

        const result = try state.mutate(mutation, color_class_buf[0..]);
        try expectEqual(expected_state, state);
        try expectEqual(State.OutputInstruction{ .Incremental = "hidden" }, result.?);
    }

    test "State.mutate::can_enable_fg_color_without_closing_anything" {
        var color_class_buf: [5]u8 = undefined;
        var state = State{ .bold = true };
        var expected_state = State{ .bold = true, .fg = 1 };
        var mutation = Mutation{ .Foreground = 1 };

        const result = try state.mutate(mutation, color_class_buf[0..]);
        try expectEqual(expected_state, state);
        try expectEqualStrings("fg-1", result.?.Incremental);
    }

    test "State.mutate::switching_fg_colors_with_one_existing_forces_rebuild" {
        var color_class_buf: [5]u8 = undefined;
        var state = State{ .fg = 1 };
        var expected_state = State{ .fg = 2 };
        var mutation = Mutation{ .Foreground = 2 };

        const result = try state.mutate(mutation, color_class_buf[0..]);
        try expectEqual(expected_state, state);
        try expectEqual(State.OutputInstruction{ .Rebuild = 1 }, result.?);
    }

    test "State.mutate::can_enable_bg_color_without_closing_anything" {
        var color_class_buf: [5]u8 = undefined;
        var state = State{ .bold = true };
        var expected_state = State{ .bold = true, .bg = 1 };
        var mutation = Mutation{ .Background = 1 };

        const result = try state.mutate(mutation, color_class_buf[0..]);
        try expectEqual(expected_state, state);
        try expectEqualStrings("bg-1", result.?.Incremental);
    }

    test "State.mutate::switching_bg_colors_with_one_existing_forces_rebuild" {
        var color_class_buf: [5]u8 = undefined;
        var state = State{ .bg = 1 };
        var expected_state = State{ .bg = 2 };
        var mutation = Mutation{ .Background = 2 };

        const result = try state.mutate(mutation, color_class_buf[0..]);
        try expectEqual(expected_state, state);
        try expectEqual(State.OutputInstruction{ .Rebuild = 1 }, result.?);
    }

    comptime {
        std.testing.refAllDecls(@This());
    }
};

const Mutation = union(enum) {
    Reset,
    BoldEnable,
    UnderscoreEnable,
    BlinkEnable,
    HiddenEnable,
    Foreground: u8,
    Background: u8,

    pub fn from_instruction(ins: []const u8) ?@This() {
        const ins_trimmed = trimLeft(u8, ins, "0");
        return switch (ins_trimmed.len) {
            // all 0's got trimmed out, leaving us with a "0" instruction aka reset
            0 => Mutation{ .Reset = {} },
            1 => switch (ins_trimmed[0]) {
                BOLD => Mutation{ .BoldEnable = {} },
                UNDERSCORE => Mutation{ .UnderscoreEnable = {} },
                BLINK => Mutation{ .BlinkEnable = {} },
                HIDDEN => Mutation{ .HiddenEnable = {} },
                else => null,
            },
            2 => switch (ins_trimmed[0]) {
                FG_FAMILY => switch (ins_trimmed[1]) {
                    '8' => null, // truecolor not supported
                    '9' => null, // FG_NONE not yet supported
                    else => Mutation{ .Foreground = color_code_from_char(ins_trimmed[1]) },
                },
                BRIGHT_FG_FAMILY => blk: {
                    if (ins_trimmed[1] < '8') {
                        break :blk Mutation{ .Foreground = bright_color_code_from_char(ins_trimmed[1]) };
                    } else {
                        break :blk null;
                    }
                },
                BG_FAMILY => switch (ins_trimmed[1]) {
                    '8' => null, // truecolor not supported
                    '9' => null, // BG_NONE not yet supported
                    else => Mutation{ .Background = color_code_from_char(ins_trimmed[1]) },
                },
                else => null,
            },
            // the only 100+ series codes we understand are bright backgrounds, so
            // we get to be *extra* lazy
            3 => switch (ins_trimmed[1]) {
                '0' => blk: {
                    if (ins_trimmed[2] < '8') {
                        break :blk Mutation{ .Background = bright_color_code_from_char(ins_trimmed[2]) };
                    } else {
                        break :blk null;
                    }
                },
                else => null,
            },
            else => null,
        };
    }

    fn color_code_from_char(char: u8) u8 {
        return char - 48;
    }

    fn bright_color_code_from_char(char: u8) u8 {
        return 8 + color_code_from_char(char);
    }
};

pub fn main() anyerror!void {
    const in = std.io.getStdIn();
    const out = std.io.getStdOut();
    var buf_in = std.io.bufferedReader(in.reader());
    var buf_out = std.io.bufferedWriter(out.writer());
    try process_stream(&buf_in, &buf_out);
}

fn process_stream(input: anytype, output: anytype) !void {
    const reader = input.reader();
    const writer = output.writer();
    var state = State{};

    var instruction_read_buf: [32]u8 = undefined;
    var span_buf: [SPAN_OPEN.len + LONGEST_SPAN_CLASS_NAME]u8 = undefined;
    var color_class_buf: [5]u8 = undefined;
    var need_to_open_spans = false;
    while (reader.readByte()) |c| {
        if (need_to_open_spans) {
            try state.write_all_open_spans(writer, color_class_buf[0..]);
            need_to_open_spans = false;
        }

        // if we get a new line, close all open tags, and reopen them on the
        // next new line (if applicable), to prevent unclosed spans or otherwise
        // interfering with HTML the caller may wrap around this output on a
        // line-by-line basis
        if (c == '\n') {
            try state.write_close_spans(writer, state.num_differing_fields());
            try writer.writeByte(c);
            // if there's anything left in the stream, we'll open new tags next
            // iteration, otherwise, the while->else will end execution anyway
            need_to_open_spans = true;
            continue;
        }

        if (c != ESCAPE_1) {
            try writer.writeByte(c);
            continue;
        }

        const c2 = try reader.readByte();
        if (c2 != ESCAPE_2) {
            // technically, malformed escape sequences are probably not useful
            // to downstream consumers, but it's not this tool's place to make
            // that determination, so dump them out verbatim
            try writer.writeByte(c);
            try writer.writeByte(c2);
            continue;
        }

        if (try reader.readUntilDelimiterOrEof(instruction_read_buf[0..], UNESCAPE)) |seq| {
            const last_possible_index = seq.len - 1;
            var instruction_start: usize = 0;
            for (seq) |sc, idx| {
                const is_end = idx == last_possible_index;

                if (is_end or sc == COMBO) {
                    const slice = if (is_end) seq[instruction_start..] else seq[instruction_start..idx];
                    if (Mutation.from_instruction(slice)) |mutation| {
                        std.log.debug("mutation: {s}", .{mutation});

                        if (try state.mutate(mutation, color_class_buf[0..])) |todo| {
                            std.log.debug("todo: {s}", .{todo});

                            switch (todo) {
                                .Incremental => |span| {
                                    const tag = try std.fmt.bufPrint(span_buf[0..], SPAN_OPEN, .{span});
                                    try writer.writeAll(tag);
                                },
                                .Rebuild => |close_count| {
                                    try state.write_close_spans(writer, close_count);
                                    try state.write_all_open_spans(writer, color_class_buf[0..]);
                                },
                            }
                        }
                    }

                    instruction_start = std.math.min(last_possible_index, idx + 1);
                }
            }
        }
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => std.log.err("error received: {s}", .{err}),
    }

    try output.flush();
}

// NOTE: all the remaining tests are integration tests of the stream parser,
// and were generated by piping whatever command is in the comments into base64
// and then wl-copy, so that the ANSI escape sequences would be reasonable-ish
// to paste in (as opposed to needing to read files off the disk at test time)

// ls -1 --color=always
//
// this is probably the easiest case I've found: opens a bold and fg-4 sequence
// that spans only a partial line on two lines, and the rest of the lines are
// uncolored
test "process_stream::simple" {
    const ls_output =
        \\G1swbRtbMDE7MzRtemlnLWNhY2hlG1swbS8KG1swMTszNG16aWctb3V0G1swbS8KG1swMG1iZWdy
        \\dWRnZS56aWcbWzBtChtbMDBtYnVpbGQuemlnG1swbQobWzAwbUNPUFlJTkcbWzBtChtbMDBtUkVB
        \\RE1FLm1kG1swbQo=
    ;
    const exp =
        \\<span class='begrudge-bold'><span class='begrudge-fg-4'>zig-cache</span></span>/
        \\<span class='begrudge-bold'><span class='begrudge-fg-4'>zig-out</span></span>/
        \\begrudge.zig
        \\build.zig
        \\COPYING
        \\Makefile
        \\README.md
    ;
}

comptime {
    std.testing.refAllDecls(@This());
}
