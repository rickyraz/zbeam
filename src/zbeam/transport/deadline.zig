//! Bounds cancelable I/O work. The losing task is joined before its borrowed
//! arguments or allocator can leave scope; a late successful result is dropped.
const std = @import("std");

pub fn run(io: std.Io, allocator: std.mem.Allocator, duration: ?std.Io.Duration, comptime operation: anytype, args: anytype, comptime drop: anytype) anyerror!@typeInfo(@TypeOf(@call(.auto, operation, args))).error_union.payload {
    if (duration == null) return @call(.auto, operation, args);
    const Result = @TypeOf(@call(.auto, operation, args));
    const Work = struct {
        fn call(bound_args: @TypeOf(args)) Result {
            return @call(.auto, operation, bound_args);
        }
    };
    const U = union(enum) { work: Result, timer: std.Io.Cancelable!void };
    var storage: [2]U = undefined;
    var select = std.Io.Select(U).init(io, &storage);
    try select.concurrent(.work, Work.call, .{args});
    defer {
        while (select.cancel()) |finished| switch (finished) {
            .work => |result| if (result) |value| drop(value, allocator) else |_| {},
            .timer => {},
        };
    }
    try select.concurrent(.timer, std.Io.sleep, .{ io, duration.?, .awake });
    return switch (try select.await()) {
        .work => |result| result,
        .timer => |result| {
            try result;
            return error.Timeout;
        },
    };
}

pub fn dropVoid(_: void, _: std.mem.Allocator) void {}

fn slow(io: std.Io) !void {
    try io.sleep(.fromSeconds(60), .awake);
}

test "timeout cancels and joins blocked I/O" {
    try std.testing.expectError(error.Timeout, run(std.testing.io, std.testing.allocator, .fromMilliseconds(10), slow, .{std.testing.io}, dropVoid));
}

const Cancellable = struct {
    started: std.Io.Event = .unset,

    fn wait(self: *@This(), io: std.Io) !void {
        self.started.set(io);
        try io.sleep(.fromSeconds(60), .awake);
    }

    fn bounded(self: *@This(), io: std.Io) anyerror!void {
        try run(io, std.testing.allocator, .fromSeconds(10), wait, .{ self, io }, dropVoid);
    }
};

test "external cancellation propagates instead of becoming a timeout" {
    const io = std.testing.io;
    var context: Cancellable = .{};
    var task = try io.concurrent(Cancellable.bounded, .{ &context, io });
    try context.started.wait(io);
    try std.testing.expectError(error.Canceled, task.cancel(io));
}
