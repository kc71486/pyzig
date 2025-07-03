//! "Header" of allocators.zig and dll_allocator.zig

pub const AllocatorResult = extern struct {
    ptr: *anyopaque,
    vtable: *align(@alignOf(*anyopaque)) const anyopaque,
    success: bool,

    pub fn init(allocator: std.mem.Allocator, success: bool) AllocatorResult {
        return .{
            .ptr = allocator.ptr,
            .vtable = @ptrCast(allocator.vtable),
            .success = success,
        };
    }
    pub fn toAllocator(allocator: AllocatorResult) std.mem.Allocator {
        return .{
            .ptr = allocator.ptr,
            .vtable = @ptrCast(allocator.vtable),
        };
    }
};

pub const isDebug: bool = switch (builtin.mode) {
    .Debug, .ReleaseSafe => true,
    .ReleaseFast, .ReleaseSmall => true,
};

const std = @import("std");
const builtin = @import("builtin");
