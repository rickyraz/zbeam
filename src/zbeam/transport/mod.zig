//! Network transport and buffer-ownership battery.
//!
//! Actor and runtime behavior are intentionally unavailable here.

pub const epmd_client = @import("epmd_client.zig");
pub const handshake_io = @import("handshake_io.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
