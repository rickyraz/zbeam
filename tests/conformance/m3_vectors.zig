const etf = @import("zbeam-etf");
const vectors = @import("zbeam-protocol-fixtures").m3_vectors;
const check = @import("m2b_vectors.zig").checkFixture;

test "independent OTP 25/26/27 custom binary request and reply frames match" {
    const peer = etf.Pid{ .node = "peer@host", .creation = 2, .id = 4, .serial = 0 };
    const actor = etf.Pid{ .node = "native@host", .creation = 1, .id = 1, .serial = 0 };
    const ref = etf.Reference{ .node = peer.node, .creation = 2, .len = 2, .ids = .{ 1, 2, 0, 0, 0 } };
    const maximum: [32]u8 = @splat(42);
    var send = [_]etf.Term{ .{ .integer = 2 }, .{ .atom = "" }, .{ .pid = actor } };
    var cmd = [_]etf.Term{ .{ .atom = "call" }, .{ .binary = "" } };
    var request = [_]etf.Term{ .{ .pid = peer }, .{ .reference = ref }, .{ .tuple = &cmd } };
    try check(vectors, "call_empty", &.{ .tuple = &send }, &.{ .tuple = &request });
    cmd[1] = .{ .binary = &maximum };
    try check(vectors, "call_max", &.{ .tuple = &send }, &.{ .tuple = &request });
    send[2] = .{ .pid = peer };
    var value = [_]etf.Term{ .{ .atom = "ok" }, .{ .binary = "" } };
    var reply = [_]etf.Term{ .{ .reference = ref }, .{ .tuple = &value } };
    try check(vectors, "reply_empty", &.{ .tuple = &send }, &.{ .tuple = &reply });
    value[1] = .{ .binary = &maximum };
    try check(vectors, "reply_max", &.{ .tuple = &send }, &.{ .tuple = &reply });
    const large: [300]u8 = @splat(42);
    value[1] = .{ .binary = &large };
    try check(vectors, "reply_large", &.{ .tuple = &send }, &.{ .tuple = &reply });
}
