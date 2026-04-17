pub fn build(b: *std.Build) !void {
    // hyperparams
    const target = b.standardTargetOptions(.{});
    const optimize: std.builtin.OptimizeMode = b.standardOptimizeOption(.{});
    // .Debug generates incompatible functions against python dll
    // .ReleaseSafe (and ReleaseSafe only) incorrectly expands __va_arg_pack in zig 0.16.0
    const optimize_c: std.builtin.OptimizeMode = if (optimize == .Debug or optimize == .ReleaseSafe) .ReleaseFast else optimize;

    // options
    const o_sys_include: ?[]const u8 = b.option([]const u8, "sysinclude", "System include path override");
    const o_lib_path: ?[]const u8 = b.option([]const u8, "libpath", "Library path override");

    // default step
    const step_install = b.getInstallStep();

    // option refine
    const sys_include: []const u8 = o_sys_include orelse
        if (target.result.os.tag == .windows) blk: {
            const home: []const u8 = try getEnvVarOwnedW(b.allocator, "USERPROFILE");
            defer b.allocator.free(home);
            break :blk try std.fs.path.join(b.allocator, &.{ home, "Appdata\\Local\\Programs\\Python\\Python312\\include" });
        } else "/usr/include/python3.12/";

    // python ffi cimport module, requires release build.
    // debug build includes symbol that doesn't exist in python312.lib.
    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/py_headers.c"),
        .target = target,
        .optimize = optimize_c,
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
    step_test.dependOn(step_install);
}

/// Windows-only. Caller must free returned memory.
/// If `key` is not valid [WTF-8](https://simonsapin.github.io/wtf-8/),
/// then `error.InvalidWtf8` is returned.
/// The value is encoded as [WTF-8](https://simonsapin.github.io/wtf-8/).
fn getEnvVarOwnedW(allocator: Allocator, key: []const u8) GetEnvVarOwnedError![]u8 {
    const result_w = blk: {
        var fba_buf: [256 * @sizeOf(u16)]u8 = undefined;
        var fba: std.heap.FixedBufferAllocator = .init(&fba_buf);
        const buffer_allocator: Allocator = fba.allocator();
        const key_w: [:0]u16 = try unicode.wtf8ToWtf16LeAllocZ(buffer_allocator, key);
        defer buffer_allocator.free(key_w);

        break :blk getenvW(key_w) orelse return GetEnvVarOwnedError.EnvironmentVariableNotFound;
    };
    // wtf16LeToWtf8Alloc can only fail with OutOfMemory
    return unicode.wtf16LeToWtf8Alloc(allocator, result_w);
}

/// Windows-only. Get an environment variable with a null-terminated, WTF-16 encoded name.
///
/// This function performs a Unicode-aware case-insensitive lookup using RtlEqualUnicodeString.
fn getenvW(key: [*:0]const u16) ?[:0]const u16 {
    const key_slice = std.mem.sliceTo(key, 0);
    // '=' anywhere but the start makes this an invalid environment variable name
    if (key_slice.len > 0 and std.mem.indexOfScalar(u16, key_slice[1..], '=') != null) {
        return null;
    }
    const ptr = windows.peb().ProcessParameters.Environment;
    var i: usize = 0;
    while (ptr[i] != 0) {
        const key_value = std.mem.sliceTo(ptr[i..], 0);

        // There are some special environment variables that start with =,
        // so we need a special case to not treat = as a key/value separator
        // if it's the first character.
        // https://devblogs.microsoft.com/oldnewthing/20100506-00/?p=14133
        const equal_search_start: usize = if (key_value[0] == '=') 1 else 0;
        const equal_index = std.mem.indexOfScalarPos(u16, key_value, equal_search_start, '=') orelse {
            // This is enforced by CreateProcess.
            // If violated, CreateProcess will fail with INVALID_PARAMETER.
            unreachable; // must contain a =
        };

        const this_key = key_value[0..equal_index];
        if (eqlIgnoreCaseWTF16(key_slice, this_key)) {
            return key_value[equal_index + 1 ..];
        }

        // skip past the NUL terminator
        i += key_value.len + 1;
    }
    return null;
}

/// Compares two WTF16 strings using the equivalent functionality of
/// `RtlEqualUnicodeString` (with case insensitive comparison enabled).
fn eqlIgnoreCaseWTF16(a: []const u16, b: []const u16) bool {
    if (a.len != b.len) return false;

    for (a, b) |a_c, b_c| {
        // The slices are always WTF-16 LE, so need to convert the elements to native
        // endianness for the uppercasing
        const a_c_native = std.mem.littleToNative(u16, a_c);
        const b_c_native = std.mem.littleToNative(u16, b_c);
        if (a_c != b_c and windows.nls.upcaseW(a_c_native) != windows.nls.upcaseW(b_c_native)) {
            return false;
        }
    }
    return true;
}

pub const GetEnvVarOwnedError = error{
    OutOfMemory,
    EnvironmentVariableNotFound,
    /// On Windows, environment variable keys provided by the user must be valid WTF-8.
    /// https://simonsapin.github.io/wtf-8/
    InvalidWtf8,
};

const builtin = @import("builtin");
const native_os = builtin.os.tag;

const std = @import("std");
const Step = std.Build.Step;
const unicode = std.unicode;
const windows = std.os.windows;
const Allocator = std.mem.Allocator;
