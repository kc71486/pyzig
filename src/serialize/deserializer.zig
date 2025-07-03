/// Deserialize source.
pub fn deserializeOne(
    T: type,
    allocator: Allocator,
    src_base: []const u8,
) SerializeError!T {
    const src: Slice = .{ .offset = 0, .len = objectSize(T) };
    return _deserializeOne(T, allocator, src_base, src);
}

/// Deserialize source into a slice.
pub fn deserializeMany(
    SliceType: type,
    allocator: Allocator,
    src_base: []const u8,
    count: usize,
) SerializeError!SliceType {
    const pointer_info = @typeInfo(SliceType).pointer;
    const sentinel_count = if (pointer_info.sentinel_ptr != null) 1 else 0;
    const src: Slice = .{ .offset = 0, .len = objectSize(pointer_info.child) * (count + sentinel_count) };
    return _deserializeMany(SliceType, allocator, src_base, src, count);
}

/// Deserialize source with custom start and end point.
pub fn _deserializeOne(
    T: type,
    allocator: Allocator,
    src_base: []const u8,
    src: Slice,
) SerializeError!T {
    assert(src.len == objectSize(T));
    var dest: T = undefined;
    try fillAny(T, allocator, src_base, src, &dest);
    return dest;
}

/// Deserialize source into a slice with custom start and end point.
pub fn _deserializeMany(
    SliceType: type,
    allocator: Allocator,
    src_base: []const u8,
    src: Slice,
    count: usize,
) SerializeError!SliceType {
    const pointer_info = @typeInfo(SliceType).pointer;
    comptime assert(pointer_info.size == .slice);
    const T = pointer_info.child;
    const childsize: usize = objectSize(T);

    const dest_slice: VarPointer(SliceType) = if (pointer_info.sentinel()) |sentinel|
        try allocator.allocSentinel(T, count, sentinel)
    else
        try allocator.alloc(T, count);

    for (dest_slice, 0..) |*dest, idx| {
        try fillAny(
            T,
            allocator,
            src_base,
            src.slice(idx * childsize, childsize),
            dest,
        );
    }
    return dest_slice;
}

pub fn fillAny(
    T: type,
    allocator: Allocator,
    src_base: []const u8,
    src: Slice,
    dest: *T,
) SerializeError!void {
    switch (@typeInfo(T)) {
        .bool, .int, .float => dest.* = try getScalar(T, src_base, src),
        .void, .null => {},
        .array => try fillArray(T, allocator, src_base, src, dest),
        .@"struct" => try fillStruct(T, allocator, src_base, src, dest),
        .@"union" => try fillUnion(T, allocator, src_base, src, dest),
        .optional => try fillOptional(T, allocator, src_base, src, dest),
        .pointer => try fillPointer(T, allocator, src_base, src, dest),
        .comptime_int, .comptime_float => return SerializeError.ComptimeType,
        .@"fn" => return SerializeError.FunctionType,
        .@"opaque" => return SerializeError.OpaqueType,
        .error_set, .error_union => return SerializeError.ErrorType,
        else => return SerializeError.UnknownType,
    }
}

pub fn getScalar(
    ScalarType: type,
    src_base: []const u8,
    src: Slice,
) SerializeError!ScalarType {
    var bytes: [objectSize(ScalarType)]u8 = undefined;
    @memcpy(&bytes, src.toConstPointer(src_base));
    const aligned: AlignedInt(ScalarType) = std.mem.readInt(AlignedInt(ScalarType), &bytes, .little);
    return switch (@typeInfo(ScalarType)) {
        .bool => aligned != 0,
        .int => @intCast(aligned),
        .float => @bitCast(aligned),
        else => return SerializeError.NotScalar,
    };
}

pub fn fillArray(
    ArrayType: type,
    allocator: Allocator,
    src_base: []const u8,
    src: Slice,
    dest_array: *ArrayType,
) SerializeError!void {
    const array_info = @typeInfo(ArrayType).array;
    const ChildType = array_info.child;
    const childsize: usize = objectSize(ChildType);
    // sentinel included
    for (dest_array, 0..) |*dest, idx| {
        try fillAny(
            ChildType,
            allocator,
            src_base,
            src.slice(idx * childsize, childsize),
            dest,
        );
    }
}

pub fn fillStruct(
    StructType: type,
    allocator: Allocator,
    src_base: []const u8,
    src: Slice,
    dest_struct: *StructType,
) SerializeError!void {
    const struct_info = @typeInfo(StructType).@"struct";
    if (struct_info.layout == .@"packed") return SerializeError.PackedLayout;
    const fields = struct_info.fields;
    var offset: usize = 0;
    inline for (fields) |field| {
        const fieldsize: usize = objectSize(field.type);
        try fillAny(
            field.type,
            allocator,
            src_base,
            src.slice(offset, fieldsize),
            &@field(dest_struct, field.name),
        );
        offset += fieldsize;
    }
}

pub fn fillUnion(
    UnionType: type,
    allocator: Allocator,
    src_base: []const u8,
    src: Slice,
    dest_union: *UnionType,
) SerializeError!void {
    const union_info = @typeInfo(UnionType).@"union";
    if (union_info.tag_type == null) return SerializeError.UntaggedUnion;
    if (union_info.layout == .@"packed") return SerializeError.PackedLayout;

    const tag_size: u16 = @alignOf(UnionType);
    const tag_offset: usize = comptime blk: {
        var _tag_offset: usize = 0;
        const fields = union_info.fields;
        for (fields) |field| {
            const fieldsize = objectSize(field.type);
            _tag_offset = @max(_tag_offset, fieldsize);
        }
        break :blk _tag_offset;
    };
    const TagType = std.meta.Int(.signed, tag_size * 8);
    const tag: TagType = try getScalar(TagType, src_base, src.slice(tag_offset, tag_size));

    const fields = union_info.fields;
    inline for (fields, 0..) |field, idx| {
        const FieldType: type = field.type;
        const fieldsize = objectSize(FieldType);
        if (tag == idx) {
            var data: FieldType = undefined;
            try fillAny(
                FieldType,
                allocator,
                src_base,
                src.slice(0, fieldsize),
                &data,
            );
            dest_union.* = @unionInit(UnionType, field.name, data);
        }
    }
}

pub fn fillOptional(
    OptionalType: type,
    allocator: Allocator,
    src_base: []const u8,
    src: Slice,
    dest_optional: *OptionalType,
) SerializeError!void {
    const optional_info = @typeInfo(OptionalType).optional;

    const tag_size: u16 = @alignOf(OptionalType);

    const FieldType: type = optional_info.child;
    const fieldsize: usize = objectSize(FieldType);
    const TagType = std.meta.Int(.signed, tag_size * 8);
    const tag: TagType = try getScalar(TagType, src_base, src.slice(fieldsize, tag_size));

    if (tag > 0) {
        var data: FieldType = undefined;
        try fillAny(
            FieldType,
            allocator,
            src_base,
            src.slice(0, fieldsize),
            &data,
        );
        dest_optional.* = data;
    } else {
        dest_optional.* = null;
    }
}

pub fn fillPointer(
    SliceType: type,
    allocator: Allocator,
    src_base: []const u8,
    src: Slice,
    dest_pointer: *SliceType,
) SerializeError!void {
    const pointer_info = @typeInfo(SliceType).pointer;
    const ChildType = pointer_info.child;
    const childSize: usize = objectSize(ChildType);

    const ptr_idx: usize = try getScalar(usize, src_base, src.slice(0, @sizeOf(usize)));
    switch (pointer_info.size) {
        .one => {
            dest_pointer.* = try _deserializeOne(
                ChildType,
                allocator,
                src_base,
                .{ .offset = ptr_idx, .len = childSize },
            );
        },
        .slice => {
            const len_idx: usize =
                try getScalar(usize, src_base, src.slice(@sizeOf(usize), @sizeOf(usize)));
            dest_pointer.* = try _deserializeMany(
                SliceType,
                allocator,
                src_base,
                .{ .offset = ptr_idx, .len = childSize * len_idx },
                len_idx,
            );
        },
        .many, .c => {
            return SerializeError.UnboundPointer;
        },
    }
}

fn VarPointer(T: type) type {
    const original_info = @typeInfo(T).pointer;
    return @Type(.{ .pointer = .{
        .size = original_info.size,
        .is_const = false,
        .is_volatile = original_info.is_volatile,
        .alignment = original_info.alignment,
        .address_space = original_info.address_space,
        .child = original_info.child,
        .is_allowzero = original_info.is_allowzero,
        .sentinel_ptr = original_info.sentinel_ptr,
    } });
}

const main = @import("main.zig");
const Slice = main.Slice;
const objectSize = main.objectSize;
const AlignedInt = main.AlignedInt;
pub const SerializeError = main.SerializeError;

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;
const assert = std.debug.assert;
