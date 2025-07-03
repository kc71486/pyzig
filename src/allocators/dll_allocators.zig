//! Standalone "library" that owns a global allocator that shared across libraries
//! within same process. This approach is not shared memory, different process
//! still has seperate variable.

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
const global_allocator: std.mem.Allocator = if (def_allocators.isDebug)
    debug_allocator.allocator()
else
    std.heap.smp_allocator;

// Only used in debug mode.
var allocator_arc: std.atomic.Value(i32) = .init(0);
var allocator_alive: std.atomic.Value(bool) = .init(true);

pub export fn init() def_allocators.AllocatorResult {
    if (def_allocators.isDebug) {
        // fetch then add
        const oldcount = allocator_arc.fetchAdd(1, .seq_cst);
        const alive = allocator_alive.load(.acquire);
        // alive will have race condition when
        // allocator_arc=1 -> deinit.fetchsub -> init.fetchadd
        // happens in order. (.seq_cst will not save this)
        if (oldcount == 0 and !alive) {
            @branchHint(.unlikely);
            return .init(undefined, false);
        }
    }
    return .init(global_allocator, true);
}

pub export fn deinit() void {
    if (def_allocators.isDebug) {
        // fetch then sub
        const oldcount = allocator_arc.fetchSub(1, .acq_rel);
        if (oldcount == 1) {
            _ = debug_allocator.deinit();
            allocator_alive.store(false, .release);
        }
    }
}

const std = @import("std");
const Mutex = std.Thread.Mutex;
const assert = std.debug.assert;

const builtin = @import("builtin");

const def_allocators = @import("def_allocators.zig");
