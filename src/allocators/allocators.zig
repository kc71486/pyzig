//! Wrapper that uses global allocator. Call `init` before using global and
//! `deinit` after finishing. `init` and `deinit` can be called multiple times
//! cross different libraries. There should be at least 1 reference of allocator
//! at all time, after all `deinit` is called, `init` can no longer be called.

/// Reference to global allocator.
pub var global: std.mem.Allocator = undefined;

var dynlib: std.DynLib = undefined;

const InitError = std.DynLib.Error || error{DeadAllocator};

/// Load and initialize global variables from `allocators.dll`.
pub fn init() InitError!void {
    dynlib = try std.DynLib.open("dynlib/allocators.dll");
    const _init = dynlib.lookup(*const fn () def_allocators.AllocatorResult, "init") orelse
        @panic("symbol \"init\" not found");
    const _global = _init();
    if (_global.success) {
        global = _global.toAllocator();
    } else {
        return InitError.DeadAllocator;
    }
}

pub fn deinit() void {
    const _deinit = dynlib.lookup(*const fn () void, "deinit") orelse
        @panic("symbol \"deinit\" not found");
    _deinit();
}

pub fn alloc(comptime T: type, n: usize) Allocator.Error![]T {
    return try global.alloc(T, n);
}

pub fn allocPanic(comptime T: type, n: usize) []T {
    return global.alloc(T, n) catch @panic("OOM");
}

pub fn create(comptime T: type) Allocator.Error!*T {
    return try global.create(T);
}

pub fn createPanic(comptime T: type) *T {
    return global.create(T) catch @panic("OOM");
}

pub fn dupe(comptime T: type, m: []const T) Allocator.Error![]T {
    return try global.dupe(T, m);
}

pub fn dupePanic(comptime T: type, m: []const T) []T {
    return global.dupe(T, m) catch @panic("OOM");
}

pub fn dupeZ(comptime T: type, m: []const T) Allocator.Error![:0]T {
    return try global.dupeZ(T, m);
}

pub fn dupeZPanic(comptime T: type, m: []const T) [:0]T {
    return global.dupeZ(T, m) catch @panic("OOM");
}

pub fn free(memory: anytype) void {
    global.free(memory);
}

pub fn destroy(memory: anytype) void {
    global.destroy(memory);
}

pub fn panicOOM() noreturn {
    @panic("OOM");
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const def_allocators = @import("def_allocators.zig");
