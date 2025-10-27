pub fn build(b: *std.Build) void {
    // hyperparams
    const target = b.standardTargetOptions(.{});
    const optimize: std.builtin.OptimizeMode = b.standardOptimizeOption(.{});
    const optimize_release: std.builtin.OptimizeMode = if (optimize == .Debug) .ReleaseSafe else optimize;

    // python ffi cimport module, requires release build.
    // debug build includes symbol that doesn't exist in python312.lib.
    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/py_headers.c"),
        .target = target,
        .optimize = optimize_release,
    });
    translate_c.addIncludePath(b.path("include"));
    const module_c = translate_c.createModule();

    // python ffi module.
    const module_py = b.addModule("py", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    module_py.addImport("c", module_c);
    module_py.addLibraryPath(b.path("lib"));
    module_py.linkSystemLibrary("python312", .{});
}

const std = @import("std");
const Step = std.Build.Step;
