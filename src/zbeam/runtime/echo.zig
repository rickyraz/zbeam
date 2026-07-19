const std = @import("std");
const etf = @import("zbeam-etf");
const distribution = @import("zbeam-protocol").distribution;

pub const Echo = struct {
    registered_name: []const u8,

    pub fn handle(self: Echo, allocator: std.mem.Allocator, packet_bytes: []const u8) !?[]u8 {
        var packet = try distribution.decodePacket(allocator, packet_bytes, .{});
        defer packet.deinit(allocator);
        if (packet == .tick) return try allocator.dupe(u8, &distribution.tickPacket());

        const route = try distribution.regSendDestination(&packet.message.control);
        if (!std.mem.eql(u8, route.name, self.registered_name)) return null;
        var payload = try packet.message.decodePayload(allocator, .{});
        defer payload.deinit(allocator);

        var control_items = [_]etf.Term{
            .{ .integer = distribution.send },
            .{ .atom = "" },
            .{ .pid = route.from },
        };
        var control = etf.Term{ .tuple = &control_items };
        return try distribution.encodePacket(allocator, &control, &payload);
    }
};

test "registered echo routes payload back to REG_SEND sender" {
    const allocator = std.testing.allocator;
    var incoming_control_items = [_]etf.Term{
        .{ .integer = distribution.reg_send },
        .{ .pid = .{ .node = "client@127.0.0.1", .id = 10, .serial = 0, .creation = 1 } },
        .{ .atom = "" },
        .{ .atom = "echo" },
    };
    var incoming_control = etf.Term{ .tuple = &incoming_control_items };
    var incoming_payload = etf.Term{ .atom = "hello" };
    const incoming = try distribution.encodePacket(allocator, &incoming_control, &incoming_payload);
    defer allocator.free(incoming);

    const response = (try (Echo{ .registered_name = "echo" }).handle(allocator, incoming)).?;
    defer allocator.free(response);
    var decoded = try distribution.decodePacket(allocator, response, .{});
    defer decoded.deinit(allocator);
    try std.testing.expectEqual(distribution.send, decoded.message.control.tuple[0].integer);
    var decoded_payload = try decoded.message.decodePayload(allocator, .{});
    defer decoded_payload.deinit(allocator);
    try std.testing.expectEqualStrings("hello", decoded_payload.atom);
}
