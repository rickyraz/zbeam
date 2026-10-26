const std = @import("std");
const handshake = @import("zbeam-protocol").handshake;

fn next(comptime Machine: type, comptime state: Machine.State, comptime event: Machine.Event) Machine.State {
    var machine = Machine{ .state = state };
    machine.advance(event) catch @compileError("invalid typed handshake transition");
    return machine.state;
}

pub fn Typed(comptime Machine: type, comptime state: Machine.State) type {
    return struct {
        pub const phase = state;

        pub fn advance(_: @This(), comptime event: Machine.Event) Typed(Machine, next(Machine, state, event)) {
            return .{};
        }
    };
}

pub const Initiator = Typed(handshake.Initiator, .idle);
pub const Acceptor = Typed(handshake.Acceptor, .idle);

test "lab12: typed local ordering follows both existing handshake machines" {
    const initiator: Initiator = .{};
    const connected = initiator.advance(.send_name).advance(.receive_status).advance(.receive_challenge).advance(.send_reply).advance(.receive_ack);
    const acceptor: Acceptor = .{};
    const accepted = acceptor.advance(.receive_name).advance(.send_status).advance(.send_challenge).advance(.receive_reply).advance(.send_ack);
    try std.testing.expectEqual(handshake.Initiator.State.connected, @TypeOf(connected).phase);
    try std.testing.expectEqual(handshake.Acceptor.State.connected, @TypeOf(accepted).phase);
    // Values remain copyable: local method ordering is not session linearity.
    _ = initiator.advance(.send_name);
}

fn finish(machine: *handshake.Initiator, payload: []const u8, expected: [16]u8) !void {
    const ack = try handshake.decodeAck(payload);
    try handshake.verifyDigest(expected, ack.digest);
    try machine.advance(.receive_ack);
}

test "lab12: typed ordering does not replace wire authentication" {
    var machine = handshake.Initiator{ .state = .reply_sent };
    const expected = handshake.cookieDigest("lab-cookie", 42);
    try std.testing.expectError(error.Truncated, finish(&machine, &.{}, expected));
    var payload: [17]u8 = undefined;
    payload[0] = 'a';
    @memset(payload[1..], 0);
    try std.testing.expectError(error.InvalidDigest, finish(&machine, &payload, expected));
    try std.testing.expectEqual(handshake.Initiator.State.reply_sent, machine.state);
    @memcpy(payload[1..], &expected);
    payload[0] = 'x';
    try std.testing.expectError(error.UnexpectedTag, finish(&machine, &payload, expected));
    payload[0] = 'a';
    try finish(&machine, &payload, expected);
    try std.testing.expectEqual(handshake.Initiator.State.connected, machine.state);
    std.debug.print("lab12 roles=2 valid_transitions=10 wire_errors=3 authenticated_ack=1\n", .{});
}
