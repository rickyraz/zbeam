//! Public package surface for `@import("zbeam")`.
const zbeam = @import("zbeam/mod.zig");

pub const actor = zbeam.actor;
pub const etf = zbeam.etf;
pub const protocol = zbeam.protocol;
pub const runtime = zbeam.runtime;
pub const transport = zbeam.transport;

test {
    @import("std").testing.refAllDecls(@This());
}
