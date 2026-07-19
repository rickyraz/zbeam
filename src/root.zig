//! Convenience battery that re-exports every public zbeam module.

pub const etf = @import("zbeam-etf");
pub const protocol = @import("zbeam-protocol");
pub const transport = @import("zbeam-transport");
pub const actor = @import("zbeam-actor");
pub const runtime = @import("zbeam-runtime");

test {
    @import("std").testing.refAllDecls(@This());
}
