pub fn build(b: *std.Build) void {
    // hyperparams
    const target = b.standardTargetOptions(.{});
    const optimize: std.builtin.OptimizeMode = b.standardOptimizeOption(.{});
    const optimize_release: std.builtin.OptimizeMode = if (optimize == .Debug) .ReleaseSafe else optimize;

    // python ffi module, requires release build.
    // debug build includes symbol that doesn't exist in python312.lib.
    const module_py = b.addModule("py", .{
        .root_source_file = b.path("src/pyffi/main.zig"),
        .target = target,
        .optimize = optimize_release,
        .link_libc = true,
    });
    module_py.addIncludePath(b.path("include"));
    module_py.addLibraryPath(b.path("lib"));
    module_py.linkSystemLibrary("python312", .{});

    // allocators module
    const module_allocators = b.addModule("allocators", .{
        .root_source_file = b.path("src/allocators/allocators.zig"),
        .target = target,
        .optimize = optimize,
    });
    _ = module_allocators;

    // dll allocators module
    const module_dll_allocators = b.addModule("dll_allocators", .{
        .root_source_file = b.path("src/allocators/dll_allocators.zig"),
        .target = target,
        .optimize = optimize,
    });

    // modules --> artifacts(compile)
    const lib_allocators = b.addLibrary(.{
        .name = "allocators",
        .root_module = module_dll_allocators,
        .linkage = .dynamic,
    });

    // perform test seems to be impossible because exported function uses some
    // python runtime stuff, and running test apparently needs it (even if it
    // didn't use it).

    // artifacts(compile) --> steps
    const install_allocators = b.addInstallArtifact(lib_allocators, .{});

    // steps and dependencies
    const step_install = b.getInstallStep();
    step_install.dependOn(&install_allocators.step);
}

const std = @import("std");
const Step = std.Build.Step;
