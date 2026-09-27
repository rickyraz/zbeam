const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const allocator = b.option(enum { process, debug, smp, libc, snmalloc }, "allocator", "Experimental application allocator (default: process)") orelse .process;
    const snmalloc_object = b.option([]const u8, "snmalloc-object", "Pinned namespaced malloc-only object built by scripts/bench/build_snmalloc.sh");
    if (allocator == .snmalloc and snmalloc_object == null) @panic("snmalloc requires -Dsnmalloc-object=/path/to/object.o");
    const link_libc = (b.option(bool, "link-libc", "Match libc linkage for allocator comparisons") orelse false) or allocator == .libc or snmalloc_object != null;
    const allocator_options = b.addOptions();
    allocator_options.addOption(@TypeOf(allocator), "allocator", allocator);
    allocator_options.addOption(bool, "snmalloc_resize", b.option(bool, "snmalloc-resize", "Reuse verified snmalloc allocation capacity without moving") orelse false);
    const allocator_options_mod = allocator_options.createModule();
    const snmalloc_mod = if (snmalloc_object) |object| blk: {
        if (target.result.os.tag != .linux or target.result.cpu.arch != .x86_64 or target.result.abi != .gnu)
            @panic("snmalloc object experiment requires native Linux x86-64 GNU ABI");
        const mod = b.createModule(.{
            .root_source_file = b.path("benchmarks/memory/snmalloc_allocator.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        mod.addImport("allocator_options", allocator_options_mod);
        mod.addObjectFile(.{ .cwd_relative = object });
        break :blk mod;
    } else null;
    const app_allocator = b.createModule(.{
        .root_source_file = b.path("src/app_allocator.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = link_libc,
    });
    app_allocator.addImport("allocator_options", allocator_options_mod);
    if (snmalloc_mod) |mod| app_allocator.addImport("snmalloc-allocator", mod);

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
            .imports = &.{
                .{ .name = "zbeam", .module = lib_mod },
                .{ .name = "app-allocator", .module = app_allocator },
            },
        }),
    });
    b.installArtifact(exe);

    const port_echo = b.addExecutable(.{
        .name = "zbeam-port-echo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/port_echo.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = link_libc,
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
    const app_allocator_tests = b.addTest(.{ .root_module = app_allocator });
    const app_allocator_tests_run = b.addRunArtifact(app_allocator_tests);
    test_unit_step.dependOn(&app_allocator_tests_run.step);

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
    const cli_smoke = b.addSystemCommand(&.{"sh"});
    cli_smoke.addFileArg(b.path("scripts/test/cli_smoke.sh"));
    cli_smoke.addArtifactArg(exe);
    test_integration_step.dependOn(&cli_smoke.step);

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

    const docker_interop_step = b.step("test-interop-docker", "Run all OTP targets with pinned Docker images (Linux)");
    const docker_interop_cmd = b.addSystemCommand(&.{"sh"});
    docker_interop_cmd.addFileArg(b.path("scripts/interop/otp_docker_matrix.sh"));
    docker_interop_cmd.step.dependOn(b.getInstallStep());
    docker_interop_step.dependOn(&docker_interop_cmd.step);

    const benchmark_step = b.step("bench-port-vs-zbeam", "Run local Erlang Port comparison");
    const benchmark_cmd = b.addSystemCommand(&.{"sh"});
    benchmark_cmd.addFileArg(b.path("scripts/bench_port_vs_zbeam.sh"));
    if (b.args) |args| benchmark_cmd.addArgs(args);
    benchmark_cmd.step.dependOn(b.getInstallStep());
    benchmark_step.dependOn(&benchmark_cmd.step);

    const backpressure_oracle = b.createModule(.{
        .root_source_file = b.path("tests/stress/backpressure_stress.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zbeam-runtime", .module = runtime_mod }},
    });
    const allocator_bench = b.addExecutable(.{
        .name = "zbeam-allocator-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/memory/allocator_compare.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zbeam", .module = lib_mod },
                .{ .name = "app-allocator", .module = app_allocator },
            },
        }),
    });
    allocator_bench.root_module.addImport("backpressure-oracle", backpressure_oracle);
    b.step("build-allocator-bench", "Install the isolated allocator benchmark").dependOn(&b.addInstallArtifact(allocator_bench, .{}).step);
    const allocator_bench_step = b.step("bench-allocators", "Run the isolated allocator workload (echo|handoff iterations bytes)");
    const allocator_bench_run = b.addRunArtifact(allocator_bench);
    if (b.args) |args| allocator_bench_run.addArgs(args);
    allocator_bench_step.dependOn(&allocator_bench_run.step);
    const allocator_tests = b.addTest(.{ .root_module = allocator_bench.root_module });
    const allocator_test_step = b.step("test-allocators", "Check the selected allocator and measured workload cleanup");
    allocator_test_step.dependOn(&b.addRunArtifact(allocator_tests).step);
    allocator_test_step.dependOn(&app_allocator_tests_run.step);
    if (snmalloc_mod) |mod| {
        const tests = b.addTest(.{ .root_module = mod });
        allocator_test_step.dependOn(&b.addRunArtifact(tests).step);
    }

    const test_all_step = b.step("test-all", "Run deterministic test suites (excludes external OTP matrix)");
    test_all_step.dependOn(test_unit_step);
    test_all_step.dependOn(test_integration_step);
    test_all_step.dependOn(test_conformance_step);
    test_all_step.dependOn(test_stress_step);

    const test_step = b.step("test", "Alias for test-all");
    test_step.dependOn(test_all_step);
}
