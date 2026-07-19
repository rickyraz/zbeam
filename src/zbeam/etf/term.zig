const std = @import("std");

pub const Pid = struct {
    node: []const u8,
    id: u32,
    serial: u32,
    creation: u32,

    pub fn deinit(self: *Pid, allocator: std.mem.Allocator) void {
        allocator.free(self.node);
        self.* = undefined;
    }
};

pub const Term = union(enum) {
    integer: i64,
    atom: []const u8,
    binary: []const u8,
    tuple: []Term,
    list: []Term,
    pid: Pid,
    nil,

    /// Releases a term returned by `decode`. Manually constructed terms must
    /// follow the same ownership convention before calling this method.
    pub fn deinit(self: *Term, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .atom => |bytes| allocator.free(bytes),
            .binary => |bytes| allocator.free(bytes),
            .tuple, .list => |items| {
                for (items) |*item| item.deinit(allocator);
                allocator.free(items);
            },
            .pid => |*pid| pid.deinit(allocator),
            .integer, .nil => {},
        }
        self.* = undefined;
    }
};
