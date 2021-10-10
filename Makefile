.POSIX:

.PHONY: all
all:
	zig build

.PHONY: test
test:
	zig test begrudge.zig

.PHONY: lint
lint:
	zig fmt --check begrudge.zig
