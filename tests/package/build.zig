//! Consumer of the fetched zbeam package; built only by package_consumer.sh.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const zbeam = b.dependency("zbeam", .{ .target = target, .optimize = optimize });
    const exe = b.addExecutable(.{
        .name = "consumer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zbeam-etf", .module = zbeam.module("zbeam-etf") },
                .{ .name = "zbeam-actor", .module = zbeam.module("zbeam-actor") },
                .{ .name = "zbeam", .module = zbeam.module("zbeam") },
            },
        }),
    });
    b.step("run", "Run the package consumer").dependOn(&b.addRunArtifact(exe).step);
}
