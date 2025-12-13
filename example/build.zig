pub fn build(b: *std.Build) void {
    // build setting
    b.reference_trace = 5;

    // hyperparams
    const target: std.Build.ResolvedTarget = b.standardTargetOptions(.{});
    const optimize: std.builtin.OptimizeMode = b.standardOptimizeOption(.{});

    // dependency pyzig module
    const pyzig = b.dependency("pyzig", .{});
    const module_py = pyzig.module("py");

    // exe main module
    const module_exe_main = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    module_exe_main.addImport("py", module_py);

    // lib root module
    const module_lib_root = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    module_lib_root.addImport("py", module_py);

    // modules --> artifacts(compile)
    const exe_main = b.addExecutable(.{
        .name = "main",
        .root_module = module_exe_main,
    });
    const lib_root = b.addLibrary(.{
        .name = "root",
        .root_module = module_lib_root,
        .linkage = .dynamic,
    });

    // artifacts(compile) --> steps
    const install_main = b.addInstallArtifact(exe_main, .{});
    const install_root = b.addInstallArtifact(lib_root, .{});

    // steps and dependencies
    const step_install = b.getInstallStep();
    step_install.dependOn(&install_main.step);
    step_install.dependOn(&install_root.step);
}

const std = @import("std");
const Step = std.Build.Step;
