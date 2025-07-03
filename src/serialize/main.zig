pub const serializer = @import("serializer.zig");
pub const deserializer = @import("deserializer.zig");

pub const serializeOne = serializer.serializeOne;
pub const serializeMany = serializer.serializeMany;

pub const deserializeOne = deserializer.deserializeOne;
pub const deserializeMany = deserializer.deserializeMany;

/// Indicates relative index compare to base.
pub const Slice = struct {
    offset: usize,
    len: usize,

    pub fn slice(self: Slice, offset: usize, len: usize) Slice {
        std.debug.assert(offset + len <= self.len);
        return .{
            .offset = self.offset + offset,
            .len = len,
        };
    }

    pub fn toPointer(self: Slice, base: []u8) []u8 {
        return base[self.offset..][0..self.len];
    }

    pub fn toConstPointer(self: Slice, base: []const u8) []const u8 {
        return base[self.offset..][0..self.len];
    }
};

/// Return serialized form `@sizeOf` T.
pub fn objectSize(T: type) usize {
    switch (@typeInfo(T)) {
        .bool, .int, .float => return @sizeOf(AlignedInt(T)),
        .void, .null => return 0,
        .array => |array_info| {
            const ChildType = array_info.child;
            const sentinel_count: usize = if (array_info.sentinel_ptr != null) 1 else 0;
            return objectSize(ChildType) * (@typeInfo(T).array.len + sentinel_count);
        },
        .@"struct" => |struct_info| {
            const fields = struct_info.fields;
            return comptime blk: {
                var total_size: usize = 0;
                for (fields) |field| {
                    total_size += objectSize(field.type);
                }
                break :blk total_size;
            };
        },
        .@"union" => |union_info| {
            const tag_size: usize = @alignOf(T);
            const tag_offset: usize = comptime blk: {
                var _tag_offset: usize = 0;
                const fields = union_info.fields;
                for (fields) |field| {
                    const fieldsize = objectSize(field.type);
                    _tag_offset = @max(_tag_offset, fieldsize);
                }
                break :blk _tag_offset;
            };
            return tag_size + tag_offset;
        },
        .optional => |optional_info| {
            const tag_size = @alignOf(T);
            return tag_size + objectSize(optional_info.child);
        },
        .pointer => |pointer_info| {
            switch (pointer_info.size) {
                .one, .many, .c => return @sizeOf(usize),
                .slice => return @sizeOf(usize) * 2,
            }
        },
        .comptime_int, .comptime_float => @compileError("ComptimeType"),
        .@"fn" => @compileError("FunctionType"),
        .@"opaque" => @compileError("OpaqueType"),
        .error_set, .error_union => @compileError("ErrorType"),
        else => @compileError("UnknownType"),
    }
}

pub fn toAlignedOffset(offset: usize, alignment: usize) usize {
    return offset +
        if (offset & (alignment - 1) > 0) alignment else 0;
}

pub fn AlignedInt(T: type) type {
    switch (@typeInfo(T)) {
        .bool => return std.meta.Int(.unsigned, 8),
        .int => |int| {
            const bits = (int.bits + 7) / 8 * 8;
            const extended_type = std.meta.Int(int.signedness, bits);
            return extended_type;
        },
        .float => |float| {
            const bits = (float.bits + 7) / 8 * 8;
            const extended_type = std.meta.Int(.signed, bits);
            return extended_type;
        },
        else => @compileError("cannot convert to byte aligned"),
    }
}

const TypeError = error{ ComptimeType, OpaqueType, ErrorType, UnknownType, NotScalar, UnboundPointer, PackedLayout, UntaggedUnion };
pub const SerializeError = TypeError || std.mem.Allocator.Error;

const std = @import("std");

test "include test.zig" {
    _ = @import("test.zig");
}
