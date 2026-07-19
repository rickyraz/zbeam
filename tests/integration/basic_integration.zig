const std = @import("std");
const zbeam = @import("zbeam");
const etf = @import("zbeam-etf");
const protocol = @import("zbeam-protocol");
const transport = @import("zbeam-transport");
const actor = @import("zbeam-actor");
const runtime = @import("zbeam-runtime");

test "integration: umbrella and independent battery imports compile" {
    std.testing.refAllDecls(zbeam);
    std.testing.refAllDecls(etf);
    std.testing.refAllDecls(protocol);
    std.testing.refAllDecls(transport);
    std.testing.refAllDecls(actor);
    std.testing.refAllDecls(runtime);
}
