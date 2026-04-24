const runtime_core = @import("runtime/core.zig");

pub const actor = @import("actor/mod.zig");
pub const etf = @import("etf/mod.zig");
pub const protocol = @import("protocol/mod.zig");
pub const runtime = @import("runtime/mod.zig");
pub const transport = @import("transport/mod.zig");

pub const add = runtime_core.add;
pub const printAnotherMessage = runtime_core.printAnotherMessage;
