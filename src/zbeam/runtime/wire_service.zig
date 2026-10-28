//! Internal owner for the separate two-worker listener and CLI profile.
const std = @import("std");
const etf = @import("zbeam-etf");
const protocol = @import("zbeam-protocol");
const transport = @import("zbeam-transport");
const Runtime = @import("task_runtime.zig");
const connection = @import("wire_connection.zig");
const worker = @import("worker.zig");

pub const Config = struct {
    node_name: []const u8,
    cookie: []const u8,
    creation: u32,
    handshake_timeout: ?std.Io.Duration = .fromSeconds(5),
    connection: connection.Config = .{},
};

pub const Service = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    config: Config,
    tasks: *Runtime,
    pids: [2]etf.Pid,
    epoch: u64 = 0,

    /// Caller keeps configuration and the I/O provider alive through deinit.
    pub fn init(io: std.Io, allocator: std.mem.Allocator, config: Config) !Service {
        const tasks = try Runtime.create(allocator, io, .{ "a", "b" });
        errdefer {
            _ = tasks.shutdown();
            tasks.deinit() catch unreachable;
        }
        var pids: [2]etf.Pid = undefined;
        for (&pids, 0..) |*pid, i| {
            while (true) {
                var bytes: [8]u8 = undefined;
                io.random(&bytes);
                pid.* = .{ .node = config.node_name, .creation = config.creation, .id = @bitCast(bytes[0..4].*), .serial = @bitCast(bytes[4..8].*) };
                if (i == 0 or !pid.eql(pids[0])) break;
            }
        }
        return .{ .io = io, .allocator = allocator, .config = config, .tasks = tasks, .pids = pids };
    }

    /// Called by one lifecycle owner after every connection has returned.
    pub fn deinit(self: *Service) void {
        _ = self.tasks.shutdown();
        self.tasks.deinit() catch unreachable;
        self.* = undefined;
    }

    /// One peer at a time; accepted work drains before this function returns.
    pub fn servePeer(self: *Service, stream: std.Io.net.Stream) !void {
        if (self.epoch == std.math.maxInt(u64)) return error.EpochExhausted;
        self.epoch += 1;
        var random: [4]u8 = undefined;
        self.io.random(&random);
        var peer = try transport.handshake_io.accept(stream, self.io, self.allocator, .{
            .node_name = self.config.node_name,
            .cookie = self.config.cookie,
            .creation = self.config.creation,
            .flags = protocol.flags.m1 | worker.monitor_flags,
            .challenge = @bitCast(random),
            .timeout = self.config.handshake_timeout,
        });
        defer peer.deinit(self.allocator);
        try connection.serve(self.io, self.allocator, stream, &peer, self.tasks, self.pids, self.epoch, self.config.connection);
    }
};

test {
    _ = @import("wire_service_test.zig");
}
