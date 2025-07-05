pub fn build(b: *std.Build) void {
    // hyperparams
    const target = b.standardTargetOptions(.{});
    const optimize: std.builtin.OptimizeMode = b.standardOptimizeOption(.{});
    const optimize_release: std.builtin.OptimizeMode = if (optimize == .Debug) .ReleaseSafe else optimize;

    // python ffi module, requires release build.
    // debug build includes symbol that doesn't exist in python312.lib.
    const module_py = b.addModule("py", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize_release,
        .link_libc = true,
    });
    module_py.addIncludePath(b.path("include"));
    module_py.addLibraryPath(b.path("lib"));
    module_py.linkSystemLibrary("python312", .{});
}

const std = @import("std");
const Step = std.Build.Step;
