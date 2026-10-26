const Initiator = @import("experiment.zig").Initiator;

test "an idle initiator cannot accept an acknowledgement" {
    const idle: Initiator = .{};
    _ = idle.advance(.receive_ack);
}
