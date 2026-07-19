//! Network transport and buffer-ownership battery.
//!
//! Actor and runtime behavior are intentionally unavailable here.

pub const epmd_client = @import("epmd_client.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
