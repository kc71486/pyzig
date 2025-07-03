const A = struct {
    outer_str: [2][:0]const u8,
    middle_str: [][:0]const u8,
    inner_count: u32,
    metadata: union(enum) {
        short_val: i16,
        medium_val: i32,
        long_val: i64,
    },
    data: [2][][]f64,

    fn init(allocator: Allocator, middle: []const [:0]const u8, inner: u32, metadata: i16) !A {
        var self: A = .{
            .outer_str = .{ &.{}, &.{} },
            .middle_str = try allocator.alloc([:0]const u8, middle.len),
            .inner_count = inner,
            .metadata = .{ .medium_val = metadata },
            .data = .{
                try allocator.alloc([]f64, middle.len),
                try allocator.alloc([]f64, middle.len),
            },
        };
        const outer_src: [2][:0]const u8 = .{ "up", "down" };
        for (&self.outer_str, outer_src) |*dst, src| {
            dst.* = try allocator.dupeZ(u8, src);
        }
        for (self.middle_str, middle) |*dst, src| {
            dst.* = try allocator.dupeZ(u8, src);
        }
        var num: f64 = 0;
        for (self.data) |dst_1| {
            for (dst_1) |*dst_2| {
                dst_2.* = try allocator.alloc(f64, inner);
                for (dst_2.*) |*dst_3| {
                    dst_3.* = num;
                    num += 1;
                }
            }
        }
        return self;
    }

    fn deinit(self: *A, allocator: Allocator) void {
        for (self.outer_str) |outer| {
            allocator.free(outer);
        }
        for (self.middle_str) |middle| {
            allocator.free(middle);
        }
        allocator.free(self.middle_str);
        for (self.data) |data_1| {
            for (data_1) |data_2| {
                allocator.free(data_2);
            }
            allocator.free(data_1);
        }
    }

    fn equals(self: *const A, other: *const A) bool {
        var result = true;
        for (self.outer_str, other.outer_str) |outer_s, outer_o| {
            result = result and std.mem.eql(u8, outer_s, outer_o);
        }
        for (self.middle_str, other.middle_str) |middle_s, middle_o| {
            result = result and std.mem.eql(u8, middle_s, middle_o);
        }
        result = result and self.inner_count == other.inner_count;
        result = result and std.meta.activeTag(self.metadata) == std.meta.activeTag(other.metadata);
        if (result) {
            result = result and switch (self.metadata) {
                .short_val => self.metadata.short_val == other.metadata.short_val,
                .medium_val => self.metadata.medium_val == other.metadata.medium_val,
                .long_val => self.metadata.long_val == other.metadata.long_val,
            };
        }
        for (self.data, other.data) |data_s, data_o| {
            for (data_s, data_o) |data_s_1, data_o_1| {
                result = result and std.mem.eql(f64, data_s_1, data_o_1);
            }
        }
        return result;
    }
};

test "process struct A" {
    const allocator: Allocator = std.testing.allocator;
    var a: A = try .init(allocator, &.{ "fire", "water", "wood" }, 5, 10);
    defer a.deinit(allocator);
    var list: ArrayList(u8) = .empty;
    defer list.deinit(allocator);
    try main.serializeOne(
        A,
        allocator,
        &list,
        &a,
    );
    const serialized: []u8 = try list.toOwnedSlice(allocator);
    defer allocator.free(serialized);
    var b: *A = try main.deserializeOne(
        A,
        allocator,
        serialized,
    );
    defer allocator.destroy(b);
    defer b.deinit(allocator);

    try std.testing.expect(a.equals(b));
}

const main = @import("main.zig");

const std = @import("std");
const ArrayList = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
