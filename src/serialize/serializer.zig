/// Serialize src into destination.
pub fn serializeOne(
    T: type,
    allocator: Allocator,
    out_list: *ArrayList(u8),
    src: *const T,
) SerializeError!void {
    const oldlen: usize = out_list.items.len;
    const addlen: usize = objectSize(T);
    // possible improvement: add padding based on alignment
    try out_list.appendNTimes(allocator, 0, addlen);
    const newslice: Slice = .{ .offset = oldlen, .len = addlen };
    try fillAny(T, allocator, out_list, newslice, src);
}

/// Serialize many src into destination. `src_slice` doesn't hold sentinel.
pub fn serializeMany(
    T: type,
    allocator: Allocator,
    out_list: *ArrayList(u8),
    src_slice: []const T,
    src_sentinel: ?T,
) SerializeError!void {
    const oldlen: usize = out_list.items.len;
    const childSize: usize = objectSize(T);
    const sentinel_count: usize = if (src_sentinel != null) 1 else 0;
    const addlen: usize = childSize * (src_slice.len + sentinel_count);
    // possible improvement: add padding based on alignment
    try out_list.appendNTimes(allocator, 0, addlen);
    const newslice: Slice = .{ .offset = oldlen, .len = addlen };
    if (src_sentinel) |sentinel| {
        try fillScalar(
            T,
            out_list,
            newslice.slice(src_slice.len * childSize, childSize),
            sentinel,
        );
    }
    for (src_slice, 0..) |data, idx| {
        try fillAny(
            T,
            allocator,
            out_list,
            newslice.slice(idx * childSize, childSize),
            &data,
        );
    }
}

/// Allocate memory for count anount of T
pub fn allocate(
    T: type,
    allocator: Allocator,
    out_list: *ArrayList(u8),
    count: usize,
) SerializeError!void {
    const addlen: usize = objectSize(T) * count;
    // possible improvement: add padding based on alignment
    try out_list.appendNTimes(allocator, 0, addlen);
}

/// Fill out dest with src, then expand and fill out_list if needed.
pub fn fillAny(
    T: type,
    allocator: Allocator,
    dest_base: *ArrayList(u8),
    dest: Slice,
    src: *const T,
) SerializeError!void {
    switch (@typeInfo(T)) {
        .bool, .int, .float => try fillScalar(T, dest_base, dest, src.*),
        .void, .null => {},
        .array => try fillArray(T, allocator, dest_base, dest, src),
        .@"struct" => try fillStruct(T, allocator, dest_base, dest, src),
        .@"union" => try fillUnion(T, allocator, dest_base, dest, src),
        .optional => try fillOptional(T, allocator, dest_base, dest, src),
        .pointer => try fillPointer(T, allocator, dest_base, dest, src.*),
        .comptime_int, .comptime_float => return SerializeError.ComptimeType,
        .@"fn" => return SerializeError.FunctionType,
        .@"opaque" => return SerializeError.OpaqueType,
        .error_set, .error_union => return SerializeError.ErrorType,
        else => return SerializeError.UnknownType,
    }
}

pub fn fillScalar(
    ScalarType: type,
    dest_base: *const ArrayList(u8),
    dest: Slice,
    src_scalar: ScalarType,
) SerializeError!void {
    assert(dest.len == objectSize(ScalarType));
    switch (@typeInfo(ScalarType)) {
        .bool, .int, .float => {},
        else => return SerializeError.NotScalar,
    }
    const aligned: AlignedInt(ScalarType) = toAlignedInt(ScalarType, src_scalar);
    var bytes: [objectSize(ScalarType)]u8 = undefined;
    std.mem.writeInt(AlignedInt(ScalarType), &bytes, aligned, .little);
    @memcpy(dest.toPointer(dest_base.items), &bytes);
}

/// Slice should hold sentinel.
pub fn fillArray(
    ArrayType: type,
    allocator: Allocator,
    dest_base: *ArrayList(u8),
    dest: Slice,
    src_array: *const ArrayType,
) SerializeError!void {
    const array_info = @typeInfo(ArrayType).array;
    const ChildType = array_info.child;
    const childsize: usize = objectSize(ChildType);

    const sentinel_opt: ?array_info.child = array_info.sentinel();
    if (sentinel_opt) |sentinel| {
        try fillScalar(
            ChildType,
            dest_base,
            dest.slice(array_info.len * childsize, childsize),
            sentinel,
        );
    }

    for (src_array, 0..) |src, idx| {
        try fillAny(
            ChildType,
            allocator,
            dest_base,
            dest.slice(idx * childsize, childsize),
            &src,
        );
    }
}

pub fn fillStruct(
    StructType: type,
    allocator: Allocator,
    out_list: *ArrayList(u8),
    dest: Slice,
    src_struct: *const StructType,
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
            out_list,
            dest.slice(offset, fieldsize),
            &@field(src_struct, field.name),
        );
        offset += fieldsize;
    }
}

pub fn fillUnion(
    UnionType: type,
    allocator: Allocator,
    dest_base: *ArrayList(u8),
    dest: Slice,
    src_union: *const UnionType,
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
    const tag: std.meta.Int(.signed, tag_size * 8) = @intFromEnum(src_union.*);
    try fillScalar(@TypeOf(tag), dest_base, dest.slice(tag_offset, tag_size), tag);

    const fields = union_info.fields;
    inline for (fields, 0..) |field, idx| {
        const FieldType: type = field.type;
        const fieldsize = objectSize(FieldType);
        if (tag == idx) {
            try fillAny(
                FieldType,
                allocator,
                dest_base,
                dest.slice(0, fieldsize),
                &@field(src_union, field.name),
            );
        }
    }
}

pub fn fillOptional(
    OptionalType: type,
    allocator: Allocator,
    dest_base: *ArrayList(u8),
    dest: Slice,
    src_optional: *const OptionalType,
) SerializeError!void {
    const optional_info = @typeInfo(OptionalType).optional;

    const tag_size: u16 = @alignOf(OptionalType);
    const tag: std.meta.Int(.signed, tag_size * 8) = if (src_optional != null) 1 else 0;

    const FieldType: type = optional_info.child;
    const fieldsize: usize = objectSize(FieldType);
    try fillScalar(@TypeOf(tag), dest_base, dest.slice(fieldsize, tag_size), tag);

    if (src_optional) |src| {
        try fillAny(
            FieldType,
            allocator,
            dest_base,
            dest.slice(0, fieldsize),
            &src,
        );
    }
}

pub fn fillPointer(
    PointerType: type,
    allocator: Allocator,
    dest_base: *ArrayList(u8),
    dest: Slice,
    src_pointer: PointerType,
) SerializeError!void {
    const pointer_info = @typeInfo(PointerType).pointer;
    const ChildType = pointer_info.child;

    const idx: usize = dest_base.items.len;
    try fillScalar(usize, dest_base, dest.slice(0, @sizeOf(usize)), idx);
    switch (pointer_info.size) {
        .one => try serializeOne(ChildType, allocator, dest_base, src_pointer),
        .slice => {
            try fillScalar(usize, dest_base, dest.slice(@sizeOf(usize), @sizeOf(usize)), src_pointer.len);
            try serializeMany(
                ChildType,
                allocator,
                dest_base,
                src_pointer,
                pointer_info.sentinel(),
            );
        },
        .many, .c => {
            return SerializeError.UnboundPointer;
        },
    }
}

/// Change value to byte aligned type.
fn toAlignedInt(T: type, value: T) AlignedInt(T) {
    switch (@typeInfo(T)) {
        .bool => return if (value) 1 else 0,
        .int => return value,
        .float => return @bitCast(value),
        else => @compileError("cannot convert to byte aligned"),
    }
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
