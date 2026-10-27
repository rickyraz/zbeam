//! Runtime composition and lifecycle battery.
//!
//! Composes the synchronous node, caller-scheduled mailbox registry and an
//! additive fixed two-task local SHA-256 runtime; no general actor scheduler.

pub const core = @import("core.zig");
pub const Echo = @import("echo.zig").Echo;
pub const Sha256 = @import("sha256.zig").Sha256;
pub const worker = @import("worker.zig");
pub const node = @import("node.zig");
pub const Runtime = @import("actors.zig").Runtime;
pub const TaskRuntime = @import("task_runtime.zig");

test {
    _ = @import("task_admission.zig");
    _ = @import("wire_output.zig");
    _ = @import("wire_monitor.zig");
    _ = @import("wire_gate.zig");
    _ = @import("wire_encode.zig");
    @import("std").testing.refAllDecls(@This());
}
