const std = @import("std");
const etf = @import("zbeam-etf");
const dist = @import("zbeam-protocol").distribution;

/// Connection-local {session:16-byte binary, sequential i32 ID, 1..32 binaries}.
/// Reply: {session, ID, concatenated independent SHA-256 digests}. No replay.
pub const BatchSha256 = struct {
    session: ?[16]u8 = null,
    next_id: i64 = 0,

    pub fn handle(self: *@This(), a: std.mem.Allocator, bytes: []const u8) !?[]u8 {
        var packet = try dist.decodePacket(a, bytes, .{ .max_packet_bytes = 2 * 1024 * 1024 });
        defer packet.deinit(a);
        if (packet == .tick) return try a.dupe(u8, &dist.tickPacket());
        const route = try dist.regSendDestination(&packet.message.control);
        if (!std.mem.eql(u8, route.name, "sha256_batch")) return null;
        var request = try packet.message.decodePayload(a, .{ .max_collection_len = 32, .max_binary_bytes = 1024 * 1024, .max_allocated_bytes = 2 * 1024 * 1024 });
        defer request.deinit(a);
        var reply = try self.compute(a, &request);
        defer reply.deinit(a);
        var fields = [_]etf.Term{ .{ .integer = dist.send }, .{ .atom = "" }, .{ .pid = route.from } };
        var control = etf.Term{ .tuple = &fields };
        return try dist.encodePacket(a, &control, &reply);
    }

    pub fn compute(self: *@This(), a: std.mem.Allocator, request: *const etf.Term) !etf.Term {
        if (request.* != .tuple or request.tuple.len != 3) return error.InvalidPayload;
        const fields = request.tuple;
        if (fields[0] != .binary or fields[0].binary.len != 16 or fields[1] != .integer or fields[2] != .list) return error.InvalidPayload;
        const id = fields[1].integer;
        if (id < 0 or id > std.math.maxInt(i32) or id != self.next_id) return error.StaleRequest;
        if (self.session) |session| if (!std.mem.eql(u8, &session, fields[0].binary)) return error.StaleSession;
        const jobs = fields[2].list;
        if (jobs.len == 0 or jobs.len > 32) return error.InvalidBatch;
        var total: usize = 0;
        for (jobs) |job| {
            if (job != .binary) return error.InvalidPayload;
            if (job.binary.len > 1024 * 1024 - total) return error.BatchTooLarge;
            total += job.binary.len;
        }
        const items = try a.alloc(etf.Term, 3);
        @memset(items, .nil);
        var result = etf.Term{ .tuple = items };
        errdefer result.deinit(a);
        // Allocate before changing the union tag, so OOM leaves a valid nil.
        const session_copy = try a.dupe(u8, fields[0].binary);
        items[0] = .{ .binary = session_copy };
        items[1] = .{ .integer = id };
        const digests = try a.alloc(u8, jobs.len * 32);
        items[2] = .{ .binary = digests };
        for (jobs, 0..) |job, i| std.crypto.hash.sha2.Sha256.hash(job.binary, digests[i * 32 ..][0..32], .{});
        self.session = fields[0].binary[0..16].*;
        self.next_id += 1;
        return result;
    }
};

fn example(a: std.mem.Allocator) !void {
    var worker: BatchSha256 = .{};
    var jobs = [_]etf.Term{ .{ .binary = "abc" }, .{ .binary = "" } };
    var fields = [_]etf.Term{ .{ .binary = "0123456789abcdef" }, .{ .integer = 0 }, .{ .list = &jobs } };
    var request = etf.Term{ .tuple = &fields };
    var result = worker.compute(a, &request) catch |err| {
        try std.testing.expectEqual(@as(i64, 0), worker.next_id);
        try std.testing.expect(worker.session == null);
        return err;
    };
    defer result.deinit(a);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("abc", &digest, .{});
    try std.testing.expectEqualSlices(u8, &digest, result.tuple[2].binary[0..32]);
    std.crypto.hash.sha2.Sha256.hash("", &digest, .{});
    try std.testing.expectEqualSlices(u8, &digest, result.tuple[2].binary[32..]);
    try std.testing.expectError(error.StaleRequest, worker.compute(a, &request));
    fields[1] = .{ .integer = 1 };
    fields[0] = .{ .binary = "fedcba9876543210" };
    try std.testing.expectError(error.StaleSession, worker.compute(a, &request));
}
test "batch exact digests, correlation and all allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, example, .{});
}
test "batch count, type and aggregate limits reject without advancing state" {
    const a = std.testing.allocator;
    var worker: BatchSha256 = .{};
    var jobs: [33]etf.Term = @splat(.{ .binary = "" });
    var fields = [_]etf.Term{ .{ .binary = "0123456789abcdef" }, .{ .integer = 0 }, .{ .list = &jobs } };
    var request = etf.Term{ .tuple = &fields };
    try std.testing.expectError(error.InvalidBatch, worker.compute(a, &request));
    fields[2] = .{ .list = jobs[0..0] };
    try std.testing.expectError(error.InvalidBatch, worker.compute(a, &request));
    fields[2] = .{ .list = jobs[0..2] };
    jobs[0] = .{ .integer = 0 };
    try std.testing.expectError(error.InvalidPayload, worker.compute(a, &request));
    const large = try a.alloc(u8, 1024 * 1024);
    defer a.free(large);
    jobs[0] = .{ .binary = large };
    jobs[1] = .{ .binary = "x" };
    try std.testing.expectError(error.BatchTooLarge, worker.compute(a, &request));
    try std.testing.expectEqual(@as(i64, 0), worker.next_id);
    fields[1] = .{ .integer = -1 };
    try std.testing.expectError(error.StaleRequest, worker.compute(a, &request));
    fields[1] = .{ .integer = @as(i64, std.math.maxInt(i32)) + 1 };
    try std.testing.expectError(error.StaleRequest, worker.compute(a, &request));
    fields[1] = .{ .integer = 0 };
    fields[0] = .{ .binary = "short" };
    try std.testing.expectError(error.InvalidPayload, worker.compute(a, &request));
}
