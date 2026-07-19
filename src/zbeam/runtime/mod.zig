//! Runtime composition and lifecycle battery.
//!
//! This module may compose actor, transport, protocol, and ETF batteries. No
//! runtime behavior is implemented yet.

pub const core = @import("core.zig");
pub const Echo = @import("echo.zig").Echo;
pub const node = @import("node.zig");
pub const Runtime = @import("actors.zig").Runtime;

test {
    @import("std").testing.refAllDecls(@This());
}
