const std = @import("std");
const transport = @import("zbeam-transport");

// Deterministic wire peer: real EPMD lifecycle coverage belongs to test-interop.
const Stub = struct {
    server: *std.Io.net.Server,
    response: []const u8,
    failure: ?anyerror = null,

    fn run(self: *Stub) void {
        self.exchange() catch |err| {
            self.failure = err;
        };
    }

    fn exchange(self: *Stub) !void {
        const io = std.testing.io;
        const stream = try self.server.accept(io);
        defer stream.close(io);
        var reader = stream.reader(io, &.{});
        var header: [2]u8 = undefined;
        try reader.interface.readSliceAll(&header);
        const length = std.mem.readInt(u16, &header, .big);
        const request = try std.testing.allocator.alloc(u8, length);
        defer std.testing.allocator.free(request);
        try reader.interface.readSliceAll(request);
        try std.testing.expect(length > 0);
        var writer = stream.writer(io, &.{});
        try writer.interface.writeAll(self.response);
    }
};

test "EPMD client handles registration and both PORT2 response forms" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const responses = [_][]const u8{
        &.{ 118, 0, 0, 0, 0, 7 },
        &.{ 119, 1 }, // Error response is only two bytes, not twelve.
        &.{ 119, 0, 0x12, 0x34, 77, 0, 0, 6, 0, 6, 0, 1, 'n', 0, 0 },
    };
    for (responses, 0..) |response, index| {
        const address: std.Io.net.IpAddress = .{ .ip4 = .loopback(0) };
        var server = try address.listen(io, .{ .reuse_address = true });
        defer server.deinit(io);
        var stub = Stub{ .server = &server, .response = response };
        var group: std.Io.Group = .init;
        defer group.cancel(io);
        try group.concurrent(io, Stub.run, .{&stub});
        const client = transport.epmd_client.Client{ .io = io, .address = server.socket.address };
        if (index == 0) {
            var registration = try client.register(allocator, .{ .port = 1234, .node_name = "n" });
            defer registration.close(io);
            try std.testing.expectEqual(@as(u32, 7), registration.creation);
        } else if (index == 1) {
            try std.testing.expectError(error.NodeNotFound, client.lookup(allocator, "absent", 0));
        } else {
            var info = try client.lookup(allocator, "n", 0);
            defer info.deinit(allocator);
            try std.testing.expectEqual(@as(u16, 0x1234), info.port);
            try std.testing.expectEqualStrings("n", info.node_name);
        }
        try group.await(io);
        if (stub.failure) |err| return err;
    }
}
