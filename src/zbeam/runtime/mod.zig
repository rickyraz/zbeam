//! Runtime composition and lifecycle battery.
//!
//! Composes the synchronous single-actor node and caller-scheduled local
//! mailbox registry. General actor task scheduling remains unimplemented.

pub const core = @import("core.zig");
pub const Echo = @import("echo.zig").Echo;
pub const Sha256 = @import("sha256.zig").Sha256;
pub const node = @import("node.zig");
pub const Runtime = @import("actors.zig").Runtime;

test {
    @import("std").testing.refAllDecls(@This());
}
