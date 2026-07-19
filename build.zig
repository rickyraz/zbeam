const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const etf_mod = b.addModule("zbeam-etf", .{
        .root_source_file = b.path("src/zbeam/etf/mod.zig"),
        .target = target,
        .optimize = optimize,
    });
    const protocol_mod = b.addModule("zbeam-protocol", .{
        .root_source_file = b.path("src/zbeam/protocol/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zbeam-etf", .module = etf_mod }},
    });
    const transport_mod = b.addModule("zbeam-transport", .{
        .root_source_file = b.path("src/zbeam/transport/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zbeam-etf", .module = etf_mod },
            .{ .name = "zbeam-protocol", .module = protocol_mod },
        },
    });
    const actor_mod = b.addModule("zbeam-actor", .{
        .root_source_file = b.path("src/zbeam/actor/mod.zig"),
        .target = target,
        .optimize = optimize,
    });
    const runtime_mod = b.addModule("zbeam-runtime", .{
        .root_source_file = b.path("src/zbeam/runtime/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zbeam-etf", .module = etf_mod },
            .{ .name = "zbeam-protocol", .module = protocol_mod },
            .{ .name = "zbeam-transport", .module = transport_mod },
            .{ .name = "zbeam-actor", .module = actor_mod },
        },
    });
    const lib_mod = b.addModule("zbeam", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zbeam-etf", .module = etf_mod },
            .{ .name = "zbeam-protocol", .module = protocol_mod },
            .{ .name = "zbeam-transport", .module = transport_mod },
            .{ .name = "zbeam-actor", .module = actor_mod },
            .{ .name = "zbeam-runtime", .module = runtime_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "zbeam",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zbeam", .module = lib_mod }},
        }),
    });
    b.installArtifact(exe);

    const port_echo = b.addExecutable(.{
        .name = "zbeam-port-echo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/port_echo.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(port_echo);

    const run_step = b.step("run", "Run the zbeam executable");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    run_step.dependOn(&run_cmd.step);

    const test_unit_step = b.step("test-unit", "Compile and test every public battery module");
    for ([_]*std.Build.Module{ lib_mod, etf_mod, protocol_mod, transport_mod, actor_mod, runtime_mod }) |module| {
        const tests = b.addTest(.{ .root_module = module });
        test_unit_step.dependOn(&b.addRunArtifact(tests).step);
    }
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    test_unit_step.dependOn(&b.addRunArtifact(exe_tests).step);

    const integration_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/integration/basic_integration.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zbeam", .module = lib_mod },
            .{ .name = "zbeam-etf", .module = etf_mod },
            .{ .name = "zbeam-protocol", .module = protocol_mod },
            .{ .name = "zbeam-transport", .module = transport_mod },
            .{ .name = "zbeam-actor", .module = actor_mod },
            .{ .name = "zbeam-runtime", .module = runtime_mod },
        },
    });
    const integration_tests = b.addTest(.{ .root_module = integration_tests_mod });
    const test_integration_step = b.step("test-integration", "Verify independent and umbrella imports");
    test_integration_step.dependOn(&b.addRunArtifact(integration_tests).step);

    const etf_fixtures_mod = b.createModule(.{
        .root_source_file = b.path("fixtures/etf/manifest.zig"),
        .target = target,
        .optimize = optimize,
    });
    const protocol_fixtures_mod = b.createModule(.{
        .root_source_file = b.path("fixtures/protocol/manifest.zig"),
        .target = target,
        .optimize = optimize,
    });
    const conformance_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/conformance/basic_conformance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zbeam-etf", .module = etf_mod },
            .{ .name = "zbeam-protocol", .module = protocol_mod },
            .{ .name = "zbeam-etf-fixtures", .module = etf_fixtures_mod },
            .{ .name = "zbeam-protocol-fixtures", .module = protocol_fixtures_mod },
        },
    });
    const conformance_tests = b.addTest(.{ .root_module = conformance_tests_mod });
    const test_conformance_step = b.step("test-conformance", "Run fixture and wire conformance tests");
    test_conformance_step.dependOn(&b.addRunArtifact(conformance_tests).step);

    const stress_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/stress/basic_stress.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zbeam-actor", .module = actor_mod },
            .{ .name = "zbeam-runtime", .module = runtime_mod },
        },
    });
    const stress_tests = b.addTest(.{ .root_module = stress_tests_mod });
    const test_stress_step = b.step("test-stress", "Run mailbox and runtime stress tests");
    test_stress_step.dependOn(&b.addRunArtifact(stress_tests).step);

    const test_interop_step = b.step("test-interop", "Run configured OTP 25-27 echo matrix");
    const test_interop_cmd = b.addSystemCommand(&.{"sh"});
    test_interop_cmd.addFileArg(b.path("scripts/interop/otp_matrix.sh"));
    test_interop_cmd.step.dependOn(b.getInstallStep());
    test_interop_step.dependOn(&test_interop_cmd.step);

    const benchmark_step = b.step("bench-port-vs-zbeam", "Run local Erlang Port comparison");
    const benchmark_cmd = b.addSystemCommand(&.{"sh"});
    benchmark_cmd.addFileArg(b.path("scripts/bench_port_vs_zbeam.sh"));
    benchmark_cmd.step.dependOn(b.getInstallStep());
    benchmark_step.dependOn(&benchmark_cmd.step);

    const test_all_step = b.step("test-all", "Run deterministic test suites (excludes external OTP matrix)");
    test_all_step.dependOn(test_unit_step);
    test_all_step.dependOn(test_integration_step);
    test_all_step.dependOn(test_conformance_step);
    test_all_step.dependOn(test_stress_step);

    const test_step = b.step("test", "Alias for test-all");
    test_step.dependOn(test_all_step);
}
