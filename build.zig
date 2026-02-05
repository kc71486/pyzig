pub fn build(b: *std.Build) !void {
    // hyperparams
    const target = b.standardTargetOptions(.{});
    const optimize: std.builtin.OptimizeMode = b.standardOptimizeOption(.{});
    const optimize_release: std.builtin.OptimizeMode = if (optimize == .Debug) .ReleaseSafe else optimize;

    // options
    const o_sys_include: ?[]const u8 = b.option([]const u8, "sysinclude", "System include path override");
    const o_lib_path: ?[]const u8 = b.option([]const u8, "libpath", "Library path override");

    // option refine
    const sys_include: []const u8 = o_sys_include orelse
        if (target.result.os.tag == .windows) blk: {
            const home: []const u8 = try std.process.getEnvVarOwned(b.allocator, "USERPROFILE");
            defer b.allocator.free(home);
            break :blk try std.fs.path.join(b.allocator, &.{ home, "Appdata\\Local\\Programs\\Python\\Python312\\include" });
        } else "/usr/include/python3.12/";

    // python ffi cimport module, requires release build.
    // debug build includes symbol that doesn't exist in python312.lib.
    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/py_headers.c"),
        .target = target,
        .optimize = optimize_release,
    });
    translate_c.addIncludePath(.{ .cwd_relative = sys_include });
    // translate_c.addIncludePath(b.path("include"));
    const module_c = translate_c.createModule();

    // python ffi module.
    const module_py = b.addModule("py", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    module_py.addImport("c", module_c);
    if (o_lib_path) |lib_path| module_py.addLibraryPath(.{ .cwd_relative = lib_path });
    // module_py.addLibraryPath(b.path("lib"));
    if (target.result.os.tag == .windows) {
        module_py.linkSystemLibrary("python312", .{});
    } else {
        module_py.linkSystemLibrary("python3.12", .{});
    }

    const test_test = b.addTest(.{
        .name = "test",
        .root_module = module_py,
    });

    const run_test = b.addRunArtifact(test_test);

    const step_test = b.step("test", "Compile all examples and run all tests");
    step_test.dependOn(&run_test.step);
}

const std = @import("std");
const Step = std.Build.Step;
