const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zunit = b.addModule("zunit", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const dap = b.dependency("dap", .{ .target = target, .optimize = optimize }).module("dap");
    const siggy = b.dependency("siggy", .{ .target = target, .optimize = optimize }).module("siggy");

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tests.root_module.addImport("dap", dap);
    tests.root_module.addImport("siggy", siggy);

    const module_tests = b.addTest(.{ .root_module = zunit });

    const test_step = b.step("test", "Run the zunit test suite");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    test_step.dependOn(&b.addRunArtifact(module_tests).step);
}
