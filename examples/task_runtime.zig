const std = @import("std");
const runtime = @import("zbeam-runtime");

pub fn main(init: std.process.Init) !void {
    const tasks = try runtime.TaskRuntime.create(init.gpa, init.io, .{ "left", "right" });
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    const left = tasks.whereis("left").?;
    const right = tasks.whereis("right").?;
    const first = try tasks.trySend(left, "abc");
    const second = try tasks.trySend(right, "abc");
    var seen: [2]bool = @splat(false);
    for (0..2) |_| {
        const result = (try tasks.nextResult()).?;
        if (result.actor_id < 1 or result.actor_id > 2) return error.UnexpectedActor;
        if (result.request_id != (if (result.actor_id == left) first else second)) return error.UnexpectedRequest;
        if (seen[result.actor_id - 1]) return error.DuplicateResult;
        seen[result.actor_id - 1] = true;
        try checkDigest(result);
    }
    _ = try tasks.stopAndJoin(left);
    if (tasks.whereis("left") != null) return error.StaleIdentity;
    const third = try tasks.trySend(right, "abc");
    const result = (try tasks.nextResult()).?;
    if (result.actor_id != right or result.request_id != third) return error.UnexpectedResult;
    try checkDigest(result);
    _ = tasks.shutdown();
    if (try tasks.nextResult() != null) return error.UnexpectedResult;
    var buffer: [128]u8 = undefined;
    var stdout: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &buffer);
    try stdout.interface.writeAll("PASS local task runtime: 3 exact digests; both actors joined\n");
    try stdout.interface.flush();
}

fn checkDigest(result: runtime.TaskRuntime.Result) !void {
    if (result.outcome != .digest) return error.UnexpectedOutcome;
    const hex = std.fmt.bytesToHex(result.outcome.digest, .lower);
    if (!std.mem.eql(u8, &hex, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")) return error.InvalidDigest;
}
