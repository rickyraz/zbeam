const std = @import("std");

/// Owned representation of an Erlang PID.
///
/// The three integers are `u32` because NEW_PID_EXT assigns exactly four
/// network-order octets (32 bits) to id, serial, and creation. `node` is copied
/// because a decoded term must not outlive or alias the receive buffer.
pub const Pid = struct {
    node: []const u8,
    id: u32,
    serial: u32,
    creation: u32,

    /// Releases the owned node atom and poisons the value so accidental reuse
    /// fails early in debug builds rather than becoming a silent use-after-free.
    pub fn deinit(self: *Pid, allocator: std.mem.Allocator) void {
        allocator.free(self.node);
        self.* = undefined;
    }
};

/// Smallest owned ETF value set needed by the first distribution peer.
///
/// This is intentionally not a universal Erlang term model: every additional
/// variant expands the untrusted-input and ownership surface.
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
