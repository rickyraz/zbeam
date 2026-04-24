const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.addModule("zbeam", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "zbeam",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zbeam", .module = lib_mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the zbeam executable");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    run_step.dependOn(&run_cmd.step);

    const unit_lib_tests = b.addTest(.{
        .root_module = lib_mod,
    });
    const run_unit_lib_tests = b.addRunArtifact(unit_lib_tests);

    const unit_exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_unit_exe_tests = b.addRunArtifact(unit_exe_tests);

    const test_unit_step = b.step("test-unit", "Run unit tests from src/");
    test_unit_step.dependOn(&run_unit_lib_tests.step);
    test_unit_step.dependOn(&run_unit_exe_tests.step);

    const integration_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/integration/basic_integration.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zbeam", .module = lib_mod },
        },
    });
    const integration_tests = b.addTest(.{ .root_module = integration_tests_mod });
    const run_integration_tests = b.addRunArtifact(integration_tests);
    const test_integration_step = b.step("test-integration", "Run integration tests");
    test_integration_step.dependOn(&run_integration_tests.step);

    const conformance_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/conformance/basic_conformance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zbeam", .module = lib_mod },
        },
    });
    const conformance_tests = b.addTest(.{ .root_module = conformance_tests_mod });
    const run_conformance_tests = b.addRunArtifact(conformance_tests);
    const test_conformance_step = b.step("test-conformance", "Run protocol conformance tests");
    test_conformance_step.dependOn(&run_conformance_tests.step);

    const stress_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/stress/basic_stress.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zbeam", .module = lib_mod },
        },
    });
    const stress_tests = b.addTest(.{ .root_module = stress_tests_mod });
    const run_stress_tests = b.addRunArtifact(stress_tests);
    const test_stress_step = b.step("test-stress", "Run stress and liveness tests");
    test_stress_step.dependOn(&run_stress_tests.step);

    const test_all_step = b.step("test-all", "Run all test suites");
    test_all_step.dependOn(&run_unit_lib_tests.step);
    test_all_step.dependOn(&run_unit_exe_tests.step);
    test_all_step.dependOn(&run_integration_tests.step);
    test_all_step.dependOn(&run_conformance_tests.step);
    test_all_step.dependOn(&run_stress_tests.step);

    const test_step = b.step("test", "Alias for test-all");
    test_step.dependOn(test_all_step);

    const bench_step = b.step("bench", "Run benchmark suite (placeholder)");
    const bench_echo = b.addSystemCommand(&.{ "sh", "-c", "echo 'bench placeholder: add scripts under scripts/bench'" });
    bench_step.dependOn(&bench_echo.step);

    const lab_step = b.step("lab", "Run lab suite (placeholder)");
    const lab_echo = b.addSystemCommand(&.{ "sh", "-c", "echo 'lab placeholder: run experiments from labs/*'" });
    lab_step.dependOn(&lab_echo.step);
}
