//! Isolated echo and bounded two-producer/one-consumer allocation workloads.
const std = @import("std");
const builtin = @import("builtin");
const zbeam = @import("zbeam");
const app = @import("app-allocator");
const Allocator = std.mem.Allocator;
const Mode = enum { echo, handoff };

pub fn main(init: std.process.Init) !void {
    defer app.deinit();
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.next();
    const mode = std.meta.stringToEnum(Mode, args.next() orelse "echo") orelse return error.InvalidWorkload;
    const iterations = try std.fmt.parseInt(usize, args.next() orelse "5000", 10);
    const size = try std.fmt.parseInt(usize, args.next() orelse "32", 10);
    if (iterations == 0 or iterations > 1_000_000 or size == 0 or size > 1024 * 1024) return error.InvalidSize;
    const raw_path = args.next();
    if (args.next() != null) return error.UnexpectedArgument;
    const raw_file = if (raw_path) |path| try std.Io.Dir.cwd().createFile(init.io, path, .{}) else null;
    defer if (raw_file) |file| file.close(init.io);
    var raw_buffer: [8192]u8 = undefined;
    var raw_writer = if (raw_file) |file| std.Io.File.Writer.initStreaming(file, init.io, &raw_buffer) else null;
    if (raw_writer) |*raw| try raw.interface.writeAll("cycle\toperation\tlatency_ns\n");

    const allocator = app.get(init.gpa);
    const request = try makeRequest(init.gpa, size);
    defer init.gpa.free(request);
    const expected = (try (zbeam.runtime.Echo{ .registered_name = "echo" }).handle(init.gpa, request)).?;
    defer init.gpa.free(expected);
    const samples = try init.gpa.alloc(u64, iterations);
    defer init.gpa.free(samples);

    // Stdlib instrumentation runs separately; timed operations use the backend directly.
    var profile = std.testing.FailingAllocator.init(allocator, .{});
    if (mode == .echo) {
        try echoSession(profile.allocator(), request, expected);
    } else {
        const bytes = try profile.allocator().alloc(u8, size);
        profile.allocator().free(bytes);
    }
    if (profile.allocated_bytes != profile.freed_bytes) return error.LeakedWorkload;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const before = try memory(init.io);
    _ = try measure(init.io, allocator, &arena, mode, request, expected, size, samples[0..@min(100, iterations)]);
    var out_buffer: [4096]u8 = undefined;
    var out = std.Io.File.Writer.initStreaming(.stdout(), init.io, &out_buffer);
    try out.interface.writeAll("allocator\tlibc\toptimize\tworkload\tarena_retain_bytes\tbytes\tcycle\titerations\tp50_ns\tp95_ns\tp99_ns\tops_per_second\trss_before_kib\trss_after_kib\trss_idle_kib\thwm_kib\tprofile_allocations\tprofile_allocated_bytes\tprofile_resizes_succeeded\n");
    for (1..4) |cycle| {
        const elapsed = try measure(init.io, allocator, &arena, mode, request, expected, size, samples);
        const after = try memory(init.io);
        try std.Io.sleep(init.io, .fromMilliseconds(100), .awake);
        const idle = try memory(init.io);
        if (raw_writer) |*raw| {
            for (samples, 0..) |ns, index| try raw.interface.print("{d}\t{d}\t{d}\n", .{ cycle, index, ns });
            try raw.interface.flush();
        }
        std.mem.sort(u64, samples, {}, std.sort.asc(u64));
        try out.interface.print("{s}\t{}\t{s}\t{s}\t{?d}\t{d}\t{d}\t{d}\t{d}\t{d}\t{d}\t{d:.1}\t{d}\t{d}\t{d}\t{d}\t{d}\t{d}\t{d}\n", .{
            @tagName(app.options.allocator), builtin.link_libc,       @tagName(builtin.mode),  @tagName(mode),                                                                        app.options.request_arena_retain, size,      cycle,    iterations,
            percentile(samples, 50),         percentile(samples, 95), percentile(samples, 99), @as(f64, @floatFromInt(iterations)) * 1e9 / @as(f64, @floatFromInt(@max(1, elapsed))), before.rss,                       after.rss, idle.rss, idle.hwm,
            profile.allocations,             profile.allocated_bytes, profile.resize_index,
        });
        try out.interface.flush();
    }
}

fn makeRequest(allocator: Allocator, size: usize) ![]u8 {
    const bytes = try allocator.alloc(u8, size);
    defer allocator.free(bytes);
    @memset(bytes, 0x5a);
    var items = [_]zbeam.etf.Term{
        .{ .integer = zbeam.protocol.distribution.reg_send },
        .{ .pid = .{ .node = "client@127.0.0.1", .id = 10, .serial = 0, .creation = 1 } },
        .{ .atom = "" },
        .{ .atom = "echo" },
    };
    var control = zbeam.etf.Term{ .tuple = &items };
    var payload = zbeam.etf.Term{ .binary = bytes };
    return zbeam.protocol.distribution.encodePacket(allocator, &control, &payload);
}

fn echoOnce(allocator: Allocator, request: []const u8, expected: []const u8) !void {
    const response = (try (zbeam.runtime.Echo{ .registered_name = "echo" }).handle(allocator, request)) orelse return error.MissingReply;
    defer allocator.free(response);
    if (!std.mem.eql(u8, response, expected)) return error.WrongReply;
}

fn echoStep(allocator: Allocator, arena: *std.heap.ArenaAllocator, request: []const u8, expected: []const u8, limit: ?usize) !void {
    defer if (limit) |cap| {
        if (!arena.reset(.{ .retain_with_limit = cap })) _ = arena.reset(.free_all);
    };
    try echoOnce(if (limit != null) arena.allocator() else allocator, request, expected);
}

fn echoSession(allocator: Allocator, request: []const u8, expected: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    try echoStep(allocator, &arena, request, expected, app.options.request_arena_retain);
}

fn measure(io: std.Io, allocator: Allocator, arena: *std.heap.ArenaAllocator, mode: Mode, request: []const u8, expected: []const u8, size: usize, samples: []u64) !u64 {
    const started = std.Io.Clock.awake.now(io);
    if (mode == .echo) {
        for (samples) |*sample| {
            const begin = std.Io.Clock.awake.now(io);
            try echoStep(allocator, arena, request, expected, app.options.request_arena_retain);
            sample.* = @intCast(begin.untilNow(io, .awake).nanoseconds);
        }
    } else try handoff(io, allocator, size, samples);
    return @intCast(started.untilNow(io, .awake).nanoseconds);
}

const Message = struct { bytes: []u8, started: std.Io.Timestamp, producer: std.Thread.Id };
const Queue = std.Io.Queue(Message);
const Producer = struct {
    io: std.Io,
    allocator: Allocator,
    queue: *Queue,
    count: usize,
    size: usize,
    failure: ?anyerror = null,

    fn run(self: *@This()) void {
        self.produce() catch |err| {
            self.failure = err;
            self.queue.close(self.io);
        };
    }
    fn produce(self: *@This()) !void {
        const id = std.Thread.getCurrentId();
        for (0..self.count) |_| {
            const started = std.Io.Clock.awake.now(self.io);
            const bytes = try self.allocator.alloc(u8, self.size);
            errdefer self.allocator.free(bytes);
            @memset(bytes, 0x5a);
            try self.queue.putOne(self.io, .{ .bytes = bytes, .started = started, .producer = id });
        }
    }
};

fn handoff(io: std.Io, allocator: Allocator, size: usize, samples: []u64) !void {
    var storage: [128]Message = undefined;
    var queue: Queue = .init(&storage);
    var producers = [_]Producer{
        .{ .io = io, .allocator = allocator, .queue = &queue, .count = samples.len / 2, .size = size },
        .{ .io = io, .allocator = allocator, .queue = &queue, .count = samples.len - samples.len / 2, .size = size },
    };
    var threads: [2]std.Thread = undefined;
    var spawned: usize = 0;
    defer {
        queue.close(io);
        for (threads[0..spawned]) |thread| thread.join();
        while (queue.getOneUncancelable(io)) |message| allocator.free(message.bytes) else |_| {}
    }
    for (&producers, &threads) |*producer, *thread| {
        thread.* = try std.Thread.spawn(.{}, Producer.run, .{producer});
        spawned += 1;
    }
    for (samples) |*sample| {
        const message = try queue.getOne(io);
        const valid = message.producer != std.Thread.getCurrentId() and std.mem.allEqual(u8, message.bytes, 0x5a);
        allocator.free(message.bytes);
        if (!valid) return error.InvalidHandoff;
        sample.* = @intCast(message.started.untilNow(io, .awake).nanoseconds);
    }
    for (threads[0..spawned]) |thread| thread.join();
    spawned = 0;
    for (producers) |producer| if (producer.failure) |err| return err;
}

fn percentile(sorted: []const u64, percent: usize) u64 {
    std.debug.assert(sorted.len > 0 and percent > 0 and percent <= 100);
    return sorted[(sorted.len * percent + 99) / 100 - 1];
}

const Memory = struct { rss: usize, hwm: usize };
fn memory(io: std.Io) !Memory {
    const file = try std.Io.Dir.cwd().openFile(io, "/proc/self/status", .{});
    defer file.close(io);
    // procfs reports size zero; a positional/sized reader treats that as EOF.
    // Fixed scratch storage keeps the sampler off the measured allocator.
    var reader = std.Io.File.Reader.initStreaming(file, io, &.{});
    var buffer: [16 * 1024]u8 = undefined;
    const len = try reader.interface.readSliceShort(&buffer);
    if (len == buffer.len) return error.ProcStatusTooLarge;
    const text = buffer[0..len];
    return .{ .rss = try memoryField(text, "VmRSS:"), .hwm = try memoryField(text, "VmHWM:") };
}
fn memoryField(text: []const u8, field: []const u8) !usize {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, field)) continue;
        var tokens = std.mem.tokenizeAny(u8, line[field.len..], " \t");
        const value = try std.fmt.parseInt(usize, tokens.next() orelse return error.InvalidProcStatus, 10);
        if (!std.mem.eql(u8, tokens.next() orelse "", "kB")) return error.InvalidProcStatus;
        return value;
    }
    return error.MissingMemoryField;
}

test "echo workload releases all logical bytes including allocation failures" {
    const allocator = app.get(std.testing.allocator);
    defer app.deinit();
    const request = try makeRequest(std.testing.allocator, 4096);
    defer std.testing.allocator.free(request);
    const expected = (try (zbeam.runtime.Echo{ .registered_name = "echo" }).handle(std.testing.allocator, request)).?;
    defer std.testing.allocator.free(expected);
    var reference = std.testing.FailingAllocator.init(allocator, .{ .resize_fail_index = 0 });
    try echoSession(reference.allocator(), request, expected);
    try std.testing.expectEqual(reference.allocated_bytes, reference.freed_bytes);
    for (0..reference.allocations) |index| {
        var failure = std.testing.FailingAllocator.init(allocator, .{ .fail_index = index, .resize_fail_index = 0 });
        // Reset retention is best effort: a handled OOM legitimately succeeds.
        echoSession(failure.allocator(), request, expected) catch |err| if (err != error.OutOfMemory) return err;
        try std.testing.expectEqual(index, failure.alloc_index);
        try std.testing.expectEqual(failure.allocated_bytes, failure.freed_bytes);
    }
}

test "request arena reuses warmed capacity and enforces a zero-retention policy" {
    const a = std.testing.allocator;
    const request = try makeRequest(a, 65536);
    defer a.free(request);
    const expected = (try (zbeam.runtime.Echo{ .registered_name = "echo" }).handle(a, request)).?;
    defer a.free(expected);
    var profile = std.testing.FailingAllocator.init(a, .{});
    var arena = std.heap.ArenaAllocator.init(profile.allocator());
    defer arena.deinit();
    try echoStep(profile.allocator(), &arena, request, expected, 1024 * 1024);
    const allocations = profile.allocations;
    try echoStep(profile.allocator(), &arena, request, expected, 1024 * 1024);
    try std.testing.expectEqual(allocations, profile.allocations);
    try std.testing.expect(arena.queryCapacity() <= 1024 * 1024);
    try echoStep(profile.allocator(), &arena, request, expected, 0);
    try std.testing.expectEqual(@as(usize, 0), arena.queryCapacity());
    try std.testing.expectEqual(profile.allocated_bytes, profile.freed_bytes);
}

test "bounded handoff frees on a different OS thread and joins producers" {
    const allocator = app.get(std.testing.allocator);
    defer app.deinit();
    var samples: [257]u64 = undefined;
    try handoff(std.testing.io, allocator, 137, &samples);
}

test "selected allocator and request policy preserve paused and canceled packet ownership" {
    const allocator = app.get(std.testing.allocator);
    defer app.deinit();
    // Only the receiver mutates the counter; inspect after both tasks join.
    var profile = std.testing.FailingAllocator.init(allocator, .{});
    try @import("backpressure-oracle").exercise(profile.allocator(), false, app.options.request_arena_retain);
    try @import("backpressure-oracle").exercise(profile.allocator(), true, app.options.request_arena_retain);
    try std.testing.expect(profile.allocated_bytes > 0);
    try std.testing.expectEqual(profile.allocated_bytes, profile.freed_bytes);
}

test "proc memory reads a zero-size virtual file as a stream" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const result = try memory(std.testing.io);
    try std.testing.expect(result.rss > 0);
    try std.testing.expect(result.hwm >= result.rss);
}

test "nearest rank and Linux memory fields are explicit" {
    try std.testing.expectEqual(@as(u64, 2), percentile(&.{ 1, 2, 3, 4 }, 50));
    try std.testing.expectEqual(@as(u64, 4), percentile(&.{ 1, 2, 3, 4 }, 99));
    try std.testing.expectEqual(@as(usize, 4096), try memoryField("VmRSS:\t 4096 kB\n", "VmRSS:"));
    try std.testing.expectError(error.MissingMemoryField, memoryField("", "VmRSS:"));
    try std.testing.expectError(error.InvalidProcStatus, memoryField("VmRSS: 1 bytes", "VmRSS:"));
}
