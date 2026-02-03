pub fn assert(value: bool) void {
    comptime {
        std.debug.assert(value);
    }
}

/// Asserts two struct has the same layout without checking field name.
///
///  ## Function Parameters
/// * `Value`: First struct.
/// * `Target`: Second struct.
///
/// ## Version
/// This function is provided by zig-sdl3-fork.
pub fn equalLayout(Value: type, Target: type) void {
    comptime {
        std.debug.assert(@sizeOf(Value) == @sizeOf(Target));
        std.debug.assert(@typeInfo(Value).@"struct".layout != .auto);
        std.debug.assert(@typeInfo(Target).@"struct".layout != .auto);
        const fields_a = @typeInfo(Value).@"struct".fields;
        const fields_b = @typeInfo(Target).@"struct".fields;
        std.debug.assert(fields_a.len == fields_b.len);
        for (fields_a, fields_b) |field_a, field_b| {
            std.debug.assert(@offsetOf(Value, field_a.name) == @offsetOf(Target, field_b.name));
            std.debug.assert(@sizeOf(field_a.type) == @sizeOf(field_b.type));
        }
    }
}

/// Asserts two struct has the same layout and name.
///
/// ## Function Parameters
/// * `Value`: First struct.
/// * `Target`: Second struct.
///
/// ## Version
/// This is provided by zig-sdl3-fork.
pub fn equalLayoutName(Value: type, Target: type) void {
    comptime {
        std.debug.assert(@sizeOf(Value) == @sizeOf(Target));
        std.debug.assert(@typeInfo(Value).@"struct".layout != .auto);
        std.debug.assert(@typeInfo(Target).@"struct".layout != .auto);
        const fields_a = @typeInfo(Value).@"struct".fields;
        const fields_b = @typeInfo(Target).@"struct".fields;
        std.debug.assert(fields_a.len == fields_b.len);
        for (fields_a, fields_b) |field_a, field_b| {
            std.debug.assert(std.mem.eql(u8, field_a.name, field_b.name));
            std.debug.assert(@offsetOf(Value, field_a.name) == @offsetOf(Target, field_b.name));
            std.debug.assert(@sizeOf(field_a.type) == @sizeOf(field_b.type));
        }
    }
}

/// Asserts packed struct has layout based on (1 << Target.value).
///
/// ## Function Parameters
/// * `Value`: Packed struct to be checked.
/// * `Target`: Referencing enum.
///
/// ## Remarks
/// Just like named tagged union, it matches the name and ignore enum order.
///
/// Unlike tagged union, packed struct may have field that enum doesn't have,
/// but not vice versa.
///
/// Only tracks enum main field, declaration is ignored.
///
/// ## Version
/// This is provided by zig-sdl3-fork.
pub fn matchPackedLayoutEnum(Value: type, Target: type) void {
    comptime {
        const enum_fields = @typeInfo(Target).@"enum".fields;
        const packed_fields = @typeInfo(Value).@"struct".fields;
        var offsets: [packed_fields.len]u32 = @splat(0);
        var prev_offset = 0;
        for (packed_fields, 0..) |packed_field, idx| {
            switch (@typeInfo(packed_field.type)) {
                .int => |int_| {
                    offsets[idx] = prev_offset;
                    prev_offset += int_.bits;
                },
                .bool => {
                    offsets[idx] = prev_offset;
                    prev_offset += 1;
                },
                else => unreachable, // type not allowed
            }
        }
        for (enum_fields) |enum_field| {
            for (packed_fields, 0..) |packed_field, idx| {
                if (std.mem.eql(u8, enum_field.name, packed_field.name)) {
                    std.debug.assert(enum_field.value == offsets[idx]);
                    break;
                }
            } else unreachable; // enum_field has no match
        }
    }
}

/// Asserts two integer type has the same bit width and signedness.
///
/// ## Function Parameters
/// * `Value`: First integer type.
/// * `Target`: Second integer type.
///
/// ## Version
/// This is provided by zig-sdl3-fork.
pub fn equalIntType(Value: type, Target: type) void {
    comptime {
        if (!(@typeInfo(Value).int.bits == @typeInfo(Target).int.bits and
            @typeInfo(Value).int.signedness == @typeInfo(Target).int.signedness))
            unreachable;
    }
}

/// Asserts A can fit into B without casting.
///
/// ## Function Parameters
/// * `A`: First integer type.
/// * `B`: Second integer type.
///
/// ## Remarks
/// The following expression should work out of the box if this passes.
/// ```
/// const a: Value = 0;
/// const b: Target = a; // no @intCast()
/// ```
///
/// ## Version
/// This is provided by zig-sdl3-fork.
pub fn fitIntType(Value: type, Target: type) void {
    comptime {
        const AInfo = @typeInfo(Value).int;
        const BInfo = @typeInfo(Target).int;
        if (AInfo.signedness == BInfo.signedness) {
            if (AInfo.bits > BInfo.bits) {
                unreachable;
            }
        } else if (AInfo.signedness == .unsigned) {
            if (AInfo.bits >= BInfo.bits) {
                unreachable;
            }
        } else unreachable; // signed -> unsigned
    }
}

/// Asserts enum "value" equals "target".
pub fn equalEnumInt(T: type, value: T, target: c_int) void {
    comptime {
        const value_cast: c_int = @intCast(@intFromEnum(value));
        std.debug.assert(target == value_cast);
    }
}

/// Asserts enum "value" equals "target".
pub fn equalEnumUInt(T: type, value: T, target: c_uint) void {
    comptime {
        const value_cast: c_uint = @intCast(@intFromEnum(value));
        std.debug.assert(target == value_cast);
    }
}

/// Asserts pacted struct "value" equals "target".
pub fn equalPackedInt(T: type, value: T, target: anytype) void {
    comptime {
        const Backing = @typeInfo(T).@"struct".backing_integer.?;
        const target_backing: Backing = @intCast(target);
        const target_cast: T = @bitCast(target_backing);
        std.debug.assert(value == target_cast);
    }
}

pub fn equalSize(Value: type, Target: type) void {
    comptime {
        std.debug.assert(@sizeOf(Value) == @sizeOf(Target));
    }
}

pub fn equalOffset(
    Value: type,
    comptime field_a: []const u8,
    Target: type,
    comptime field_b: []const u8,
) void {
    comptime {
        std.debug.assert(@offsetOf(Value, field_a) == @offsetOf(Target, field_b));
    }
}

/// Asserts field of type T has same offset as target.
pub fn hasOffset(T: type, comptime field_name: []const u8, target: usize) void {
    comptime {
        std.debug.assert(@offsetOf(T, field_name) == target);
    }
}

pub fn equal(value: anytype, target: anytype) void {
    comptime {
        std.debug.assert(value == target);
    }
}

const std = @import("std");
