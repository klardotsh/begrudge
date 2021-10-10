.POSIX:

.PHONY: all
all:
	zig build

.PHONY: test
test:
	zig test begrudge.zig
