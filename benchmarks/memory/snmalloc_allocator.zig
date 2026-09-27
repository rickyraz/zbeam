//! Experimental, namespaced snmalloc C ABI. No global malloc interposition.
const std = @import("std");
const options = @import("allocator_options");
const Allocator = std.mem.Allocator;
extern fn zbeam_sn_posix_memalign(*?*anyopaque, usize, usize) c_int;
extern fn zbeam_sn_free(?*anyopaque) void;
extern fn zbeam_sn_malloc_usable_size(?*anyopaque) usize;

pub const allocator: Allocator = .{
    .ptr = undefined,
    .vtable = &.{
        .alloc = alloc,
        .free = free,
        .resize = if (options.snmalloc_resize) resize else Allocator.noResize,
        .remap = if (options.snmalloc_resize) remap else Allocator.noRemap,
    },
};

fn alloc(_: *anyopaque, len: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
    if (len > std.math.maxInt(isize)) return null;
    var ptr: ?*anyopaque = null;
    if (zbeam_sn_posix_memalign(&ptr, @max(@sizeOf(usize), alignment.toByteUnits()), len) != 0) return null;
    return @ptrCast(ptr);
}
fn free(_: *anyopaque, bytes: []u8, _: std.mem.Alignment, _: usize) void {
    zbeam_sn_free(bytes.ptr);
}
fn resize(_: *anyopaque, bytes: []u8, _: std.mem.Alignment, new_len: usize, _: usize) bool {
    // malloc_usable_size is valid only for this backend's allocation base.
    // Unsized free preserves physical class identity after a logical resize.
    return new_len <= zbeam_sn_malloc_usable_size(bytes.ptr);
}
fn remap(ctx: *anyopaque, bytes: []u8, alignment: std.mem.Alignment, new_len: usize, ra: usize) ?[*]u8 {
    return if (resize(ctx, bytes, alignment, new_len, ra)) bytes.ptr else null;
}

test "snmalloc alignment, ownership routing and failed growth preserve bytes" {
    inline for (.{ 1, 16, 64, 4096, 65536 }) |alignment| {
        for ([_]usize{ 0, 1, 17, 129, 4097, 65537 }) |len| {
            var bytes = try allocator.alignedAlloc(u8, .fromByteUnits(alignment), len);
            defer allocator.free(bytes);
            try std.testing.expectEqual(@as(usize, 0), @intFromPtr(bytes.ptr) % alignment);
            if (len > 0) try std.testing.expect(zbeam_sn_malloc_usable_size(bytes.ptr) >= len);
            @memset(bytes, 0x5a);
            bytes = try allocator.realloc(bytes, len + 513);
            try std.testing.expectEqual(@as(usize, 0), @intFromPtr(bytes.ptr) % alignment);
            try std.testing.expect(std.mem.allEqual(u8, bytes[0..len], 0x5a));
            @memset(bytes, 0xa5);
            try std.testing.expectError(error.OutOfMemory, allocator.realloc(bytes, std.math.maxInt(usize)));
            try std.testing.expect(std.mem.allEqual(u8, bytes, 0xa5));
        }
    }
}

test "snmalloc optional resize does not move or exceed physical capacity" {
    var bytes = try allocator.alignedAlloc(u8, .fromByteUnits(4096), 113);
    defer allocator.free(bytes);
    const ptr = bytes.ptr;
    const capacity = zbeam_sn_malloc_usable_size(ptr);
    @memset(bytes, 0x5a);
    try std.testing.expect(!allocator.resize(bytes, capacity + 1));
    if (options.snmalloc_resize) {
        try std.testing.expect(allocator.resize(bytes, capacity));
        bytes.len = capacity;
        @memset(bytes[113..], 0xa5);
        try std.testing.expect(std.mem.allEqual(u8, bytes[0..113], 0x5a));
        bytes = allocator.remap(bytes, 17) orelse return error.UnexpectedRemapFailure;
        try std.testing.expectEqual(@intFromPtr(ptr), @intFromPtr(bytes.ptr));
        try std.testing.expect(std.mem.allEqual(u8, bytes, 0x5a));
    } else try std.testing.expect(!allocator.resize(bytes, 17));
}

test "snmalloc messages outlive producer thread exit and repeated TLS teardown" {
    const Producer = struct {
        bytes: ?[]u8 = null,
        failure: ?anyerror = null,
        fn run(self: *@This()) void {
            const bytes = allocator.alloc(u8, 4097) catch |err| {
                self.failure = err;
                return;
            };
            @memset(bytes, 0x5a);
            self.bytes = bytes;
        }
    };
    for (0..64) |_| {
        var producer: Producer = .{};
        const thread = try std.Thread.spawn(.{}, Producer.run, .{&producer});
        thread.join();
        if (producer.failure) |err| return err;
        const bytes = producer.bytes orelse return error.MissingAllocation;
        defer allocator.free(bytes);
        try std.testing.expect(std.mem.allEqual(u8, bytes, 0x5a));
    }
}

test "snmalloc Io Group cancellation releases worker-owned payload" {
    const Task = struct {
        ready: std.Io.Event = .unset,
        profile: std.testing.FailingAllocator = .init(allocator, .{}),
        failure: ?anyerror = null,
        fn run(self: *@This(), io: std.Io) void {
            const bytes = self.profile.allocator().alloc(u8, 65537) catch |err| {
                self.failure = err;
                self.ready.set(io);
                return;
            };
            defer self.profile.allocator().free(bytes);
            @memset(bytes, 0x5a);
            self.ready.set(io);
            std.Io.sleep(io, .fromSeconds(60), .awake) catch |err| {
                self.failure = err;
            };
        }
    };
    const io = std.testing.io;
    var task: Task = .{};
    var group: std.Io.Group = .init;
    defer group.cancel(io);
    try group.concurrent(io, Task.run, .{ &task, io });
    try task.ready.wait(io);
    group.cancel(io);
    try std.testing.expectEqual(@as(anyerror, error.Canceled), task.failure.?);
    try std.testing.expectEqual(task.profile.allocated_bytes, task.profile.freed_bytes);
    try std.testing.expect(task.profile.allocated_bytes > 0);
}
