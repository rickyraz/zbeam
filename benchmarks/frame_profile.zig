//! Same-binary attribution, not an end-to-end performance claim.
const std = @import("std");
const z = @import("zbeam");
const A = std.mem.Allocator;

fn legacy(a: A, control: *const z.etf.Term, payload: *const z.etf.Term) ![]u8 {
    const c = try z.etf.encode(a, control);
    defer a.free(c);
    const p = try z.etf.encode(a, payload);
    defer a.free(p);
    const out = try a.alloc(u8, 5 + c.len + p.len);
    std.mem.writeInt(u32, out[0..4], @intCast(out.len - 4), .big);
    out[4] = 112;
    @memcpy(out[5..][0..c.len], c);
    @memcpy(out[5 + c.len ..], p);
    return out;
}

pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.next();
    const name = args.next() orelse "process";
    const a = if (std.mem.eql(u8, name, "smp")) std.heap.smp_allocator else if (std.mem.eql(u8, name, "process")) init.gpa else return error.InvalidAllocator;
    const reverse = std.mem.eql(u8, args.next() orelse "forward", "reverse");
    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.Writer.initStreaming(.stdout(), init.io, &buffer);
    try out.interface.writeAll("allocator\tstage\tbytes\tp50_ns\tp99_ns\tallocations\tallocated_bytes\n");
    var data: [65536]u8 = @splat(90);
    var control = z.etf.Term{ .integer = 2 };
    for ([_]usize{ 32, 4096, 65536 }) |size| {
        var payload = z.etf.Term{ .binary = data[0..size] };
        const expected = try legacy(a, &control, &payload);
        defer a.free(expected);
        for (0..2) |index| {
            const old = (index == 0) != reverse;
            var profile = std.testing.FailingAllocator.init(a, .{});
            const p = if (old) try legacy(profile.allocator(), &control, &payload) else try z.protocol.distribution.encodePacket(profile.allocator(), &control, &payload);
            if (!std.mem.eql(u8, expected, p)) return error.WrongFrame;
            profile.allocator().free(p);
            if (profile.allocated_bytes != profile.freed_bytes) return error.Leak;
            var times: [1000]i96 = undefined;
            for (0..1100) |i| {
                const start = std.Io.Clock.awake.now(init.io);
                const bytes = if (old) try legacy(a, &control, &payload) else try z.protocol.distribution.encodePacket(a, &control, &payload);
                if (!std.mem.eql(u8, expected, bytes)) return error.WrongFrame;
                a.free(bytes);
                if (i >= 100) times[i - 100] = start.untilNow(init.io, .awake).nanoseconds;
            }
            std.mem.sort(i96, &times, {}, std.sort.asc(i96));
            try out.interface.print("{s}\t{s}\t{d}\t{d}\t{d}\t{d}\t{d}\n", .{ name, if (old) "legacy" else "append", size, times[499], times[989], profile.allocations, profile.allocated_bytes });
        }
    }
    var timer: [1000]i96 = undefined;
    for (&timer) |*t| {
        const start = std.Io.Clock.awake.now(init.io);
        try z.transport.deadline.run(init.io, a, .fromSeconds(5), noWork, .{}, z.transport.deadline.dropVoid);
        t.* = start.untilNow(init.io, .awake).nanoseconds;
    }
    std.mem.sort(i96, &timer, {}, std.sort.asc(i96));
    try out.interface.print("{s}\tdeadline_noop\t0\t{d}\t{d}\tNA\tNA\n", .{ name, timer[499], timer[989] });
    try out.interface.flush();
}
fn noWork() !void {}
