//! Pure EPMD, handshake, and distribution-protocol battery.
//!
//! This module models bytes and state transitions without owning sockets.

pub const epmd = @import("epmd.zig");
pub const handshake = @import("handshake.zig");
pub const distribution = @import("distribution.zig");
pub const flags = @import("flags.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
