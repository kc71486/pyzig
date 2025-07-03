pub fn main() !void {
    const cwd = std.fs.cwd();
    const srcdir = try cwd.openDir("src", .{});
    const use_zig: bool = if (srcdir.access("environment.pyi", .{}))
        true
    else |err| switch (err) {
        error.FileNotFound => false,
        else => return err,
    };
    const stdout = std.io.getStdOut();
    if (use_zig) {
        try srcdir.rename("environment.pyd", "environmentz.pyd");
        try srcdir.rename("environment.pyi", "environmentz.pyi");
        try srcdir.rename("environmentp.py", "environment.py");
        try stdout.writeAll("using environment py");
    } else {
        try srcdir.rename("environmentz.pyd", "environment.pyd");
        try srcdir.rename("environmentz.pyi", "environment.pyi");
        try srcdir.rename("environment.py", "environmentp.py");
        try stdout.writeAll("using environment zig");
    }
}

const std = @import("std");
