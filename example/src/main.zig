// Requires python312.dll to run.

pub fn main() !void {
    py.Interpreter.initialize();
    try mainInner();
    try py.Interpreter.finalize();
}

pub fn mainInner() !void {
    const str = "hello world";
    const str_obj: *py.UnicodeObject = .fromString(str);
    defer py.DecRef(str_obj.toObject());
    try py.Builtin.print(str_obj.toObject());
}

const std = @import("std");
const py = @import("py");
