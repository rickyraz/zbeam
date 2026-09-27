//! Executable/lab choice only. No battery imports this module.
const std = @import("std");
pub const options = @import("allocator_options");
var diagnostic: std.heap.DebugAllocator(.{}) = .init;

pub fn get(process_allocator: std.mem.Allocator) std.mem.Allocator {
    return switch (options.allocator) {
        .process => process_allocator,
        .debug => diagnostic.allocator(),
        .smp => std.heap.smp_allocator,
        .libc => std.heap.c_allocator,
    };
}

pub fn deinit() void {
    if (options.allocator == .debug) {
        std.debug.assert(diagnostic.deinit() == .ok);
        diagnostic = .init;
    }
}

test "selected application allocator preserves over-alignment and realloc data" {
    const allocator = get(std.testing.allocator);
    defer deinit();
    var bytes = try allocator.alignedAlloc(u8, .fromByteUnits(4096), 113);
    defer allocator.free(bytes);
    @memset(bytes, 0x5a);
    bytes = try allocator.realloc(bytes, 65537);
    try std.testing.expectEqual(@as(usize, 0), @intFromPtr(bytes.ptr) % 4096);
    try std.testing.expect(std.mem.allEqual(u8, bytes[0..113], 0x5a));
}
