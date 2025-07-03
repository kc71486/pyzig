//! Disclaimer: This only works with python 3.12.x release version, any other
//! version are not guaranteed to match.
//!
//! Reference Counting Term: (borrow reference by default)
//! * borrow reference (argument): caller owns the reference
//! * steal reference (argument): caller doesn't own the reference
//! * borrow reference (return): caller doesn't own reference
//! * new reference (return): caller owns the reference
//!
//! Contents:
//! * Base Object type
//! * Type Object (object metadata)
//! * Builtin types
//! * Python Error functions and types
//! * Module creation / declarations
//! * Member creation / declarations
//! * Method creation / declarations
//! * Argument parsing and building
//! * Memory management
//! * Python Object wrapper
//! * Import / Call
//! * Misc helper
//! * Zig error set
//! * Imports

// ========================================================================= //
// Base Object type

/// Every pointer to a Python object can be cast to a Object*. Zig side.
pub const Object = extern struct {
    /// Reference counter.
    rc: extern union {
        ob_refcnt: isize,
        ob_refcnt_split: if (@sizeOf(isize) == 8) [2]u32 else u32,
    },
    /// Object metadata.
    ob_type: ?*TypeObject,

    pub fn init(ob_type: ?*TypeObject) Object {
        return .{
            .rc = .{ .ob_refcnt = 1 },
            .ob_type = ob_type,
        };
    }

    pub fn fromC(object: *c.PyObject) *Object {
        return @ptrCast(object);
    }

    /// Only for function compatibilty. It never fails.
    pub fn fromObject(object: *Object) TypeError!*Object {
        return object;
    }

    pub fn toC(self: *Object) *c.PyObject {
        return @ptrCast(self);
    }

    /// Only for function compatibilty.
    pub fn toObject(self: *Object) *Object {
        return self;
    }
};

pub const PyObject_HEAD = @compileError("place 'ob_base: PyObject,' at the start of the struct");

/// Every pointer to a variable-size Python object can be cast to a
/// VarObject*. Zig side.
pub const VarObject = extern struct {
    ob_base: Object,
    ob_size: isize,

    pub fn init(ob_type: ?*TypeObject, size: isize) VarObject {
        return .{
            .ob_base = .{
                .rc = .{ .ob_refcnt = 1 },
                .ob_type = ob_type,
            },
            .ob_size = size,
        };
    }

    pub fn fromObject(object: *Object) *VarObject {
        // I dont know if there is a safer way to convert it.
        return @fieldParentPtr("ob_base", object);
    }

    pub fn toC(self: *VarObject) *c.PyVarObject {
        return @ptrCast(self);
    }

    pub fn toObject(self: *VarObject) *Object {
        return &self.ob_base;
    }
};

// ========================================================================= //
// Type Object (object metadata)

/// Object metadata.
pub const TypeObject = extern struct {
    ob_base: VarObject,
    tp_name: ?[*:0]const u8 = null,
    tp_basicsize: isize = 0,
    tp_itemsize: isize = 0,
    tp_dealloc: c.destructor = null,
    tp_vectorcall_offset: isize = 0,
    tp_getattr: c.getattrfunc = null,
    tp_setattr: c.setattrfunc = null,
    tp_as_async: ?[*]c.PyAsyncMethods = null,
    tp_repr: c.reprfunc = null,
    tp_as_number: ?[*]c.PyNumberMethods = null,
    tp_as_sequence: ?[*]c.PySequenceMethods = null,
    tp_as_mapping: ?[*]c.PyMappingMethods = null,
    tp_hash: c.hashfunc = null,
    tp_call: c.ternaryfunc = null,
    tp_str: c.reprfunc = null,
    tp_getattro: c.getattrofunc = null,
    tp_setattro: c.setattrofunc = null,
    tp_as_buffer: ?[*]c.PyBufferProcs = null,
    tp_flags: Flags = .DEFAULT,
    tp_doc: ?[*:0]const u8 = null,
    tp_traverse: c.traverseproc = null,
    tp_clear: c.inquiry = null,
    tp_richcompare: c.richcmpfunc = null,
    tp_weaklistoffset: isize = 0,
    tp_iter: c.getiterfunc = null,
    tp_iternext: c.iternextfunc = null,
    tp_methods: ?[*]c.PyMethodDef = null,
    tp_members: ?[*]c.PyMemberDef = null,
    tp_getset: ?[*]c.PyGetSetDef = null,
    tp_base: ?[*]TypeObject = null,
    tp_dict: ?[*]c.PyObject = null,
    tp_descr_get: c.descrgetfunc = null,
    tp_descr_set: c.descrsetfunc = null,
    tp_dictoffset: isize = 0,
    tp_init: c.initproc = null,
    tp_alloc: c.allocfunc = null,
    tp_new: c.newfunc = null,
    tp_free: c.freefunc = null,
    tp_is_gc: c.inquiry = null,
    tp_bases: ?[*]c.PyObject = null,
    tp_mro: ?[*]c.PyObject = null,
    tp_cache: ?[*]c.PyObject = null,
    tp_subclasses: ?*anyopaque = null,
    tp_weaklist: ?[*]c.PyObject = null,
    tp_del: c.destructor = null,
    tp_version_tag: u32 = 0,
    tp_finalize: c.destructor = null,
    tp_vectorcall: c.vectorcallfunc = null,
    tp_watched: u8 = 0,

    pub const Flags = packed struct(c_ulong) {
        _0: u1 = 0,
        STATIC_BUILTIN: bool = false,
        _2: u1 = 0,
        MANAGED_WEAKREF: bool = false,
        MANAGED_DICT: bool = false,
        SEQUENCE: bool = false,
        MAPPING: bool = false,
        DISALLOW_INSTANTIATION: bool = false,
        IMMUTABLETYPE: bool = false,
        HEAPTYPE: bool = false,
        BASETYPE: bool = false,
        HAVE_VECTORCALL: bool = false,
        READY: bool = false,
        READYING: bool = false,
        HAVE_GC: bool = false,
        HAVE_STACKLESS_EXTENSION: u2 = 0,
        METHOD_DESCRIPTOR: bool = false,
        _18: u1 = 0,
        VALID_VERSION_TAG: bool = false,
        IS_ABSTRACT: bool = false,
        _21: u1 = 0,
        MATCH_SELF: bool = false,
        ITEMS_AT_END: bool = false,
        LONG_SUBCLASS: bool = false,
        LIST_SUBCLASS: bool = false,
        TUPLE_SUBCLASS: bool = false,
        BYTES_SUBCLASS: bool = false,
        UNICODE_SUBCLASS: bool = false,
        DICT_SUBCLASS: bool = false,
        BASE_EXC_SUBCLASS: bool = false,
        TYPE_SUBCLASS: bool = false,
        // defalut python has HAVE_STACKLESS_EXTENSION disabled
        pub const DEFAULT: Flags = .{};
        pub const PREHEADER: Flags = .{ .MANAGED_WEAKREF = true, .MANAGED_DICT = true };
    };

    pub fn init(
        name: ?[*:0]const u8,
        doc: ?[*:0]const u8,
        basicsize: isize,
        itemsize: isize,
        newfunc: c.newfunc,
    ) TypeObject {
        return .{
            .ob_base = VarObject.init(null, 0),
            .tp_name = name,
            .tp_doc = doc,
            .tp_basicsize = basicsize,
            .tp_itemsize = itemsize,
            .tp_flags = Flags.DEFAULT,
            .tp_new = newfunc,
        };
    }

    pub fn fromC(object: *c.PyTypeObject) *TypeObject {
        return @ptrCast(object);
    }

    pub fn fromObject(object: *Object) TypeError!*TypeObject {
        // I dont know if there is a safer way to convert it.
        return @fieldParentPtr("ob_base", object);
    }

    pub fn toC(self: *TypeObject) *c.PyTypeObject {
        return @ptrCast(self);
    }

    pub fn toObject(self: *TypeObject) *Object {
        return &self.ob_base.ob_base;
    }

    // Finalize a type object. Set exception and return ModuleError when failed.
    pub fn ready(self: *TypeObject) ModuleError!void {
        if (c.PyType_Ready(self.toC()) < 0) {
            return ModuleError.PyType;
        }
    }

    /// allocate a new instance. Set exception and return AllocError when failed.
    pub fn alloc(self: *TypeObject) MemoryError!*Object {
        return Object.fromC(self.tp_alloc.?(self.toC(), 0) orelse return MemoryError.PyAlloc);
    }

    pub fn free(self: *TypeObject, obj: Object) void {
        self.tp_free.?(obj.toC());
    }
};

// ========================================================================= //
// Builtin types

/// None object type. Basically an empty c.PyObject.
pub const NoneObject = Object;
pub extern var _Py_NoneStruct: c.PyObject;
pub fn Py_None() *NoneObject {
    return @ptrCast(&_Py_NoneStruct);
}

/// Integer object type, immutable, field ob_digit only means it takes at
/// least 1 digit. It may take more if the number is greater than 2^30.
pub const LongObject = extern struct {
    ob_base: Object,
    long_value: c._PyLongValue,

    pub const _PyLongValue = extern struct {
        lv_tag: usize,
        ob_digit: [1]u32,
    };

    /// Make the object an int if possible, otherwise set exception and return error.
    pub fn fromObject(object: *Object) TypeError!*LongObject {
        if (isLong(object)) {
            return fromObjectFast(object);
        } else {
            Err.setString(PyExc_TypeError, "not an int");
            return TypeError.PyType;
        }
    }

    /// Make the object an int without checking.
    pub fn fromObjectFast(object: *Object) *LongObject {
        return @fieldParentPtr("ob_base", object);
    }

    pub fn toC(self: *LongObject) *c.PyLongObject {
        return @ptrCast(self);
    }

    pub fn toObject(self: *LongObject) *Object {
        return &self.ob_base;
    }

    pub fn isLong(obj: *Object) bool {
        return c.PyLong_Check(obj.toC()) != 0;
    }

    /// Returns a new reference.
    pub fn fromInt(T: type, value: T) NumericError!*LongObject {
        const int_info = @typeInfo(T).int;
        const convert_fn = blk: {
            switch (int_info.bits) {
                0...64 => {
                    if (int_info.signedness == .signed) {
                        if (@sizeOf(c_long) == 8)
                            break :blk c.PyLong_FromLong
                        else
                            break :blk c.PyLong_FromLongLong;
                    } else {
                        if (@sizeOf(c_long) == 8)
                            break :blk c.PyLong_FromUnsignedLong
                        else
                            break :blk c.PyLong_FromUnsignedLongLong;
                    }
                },
                else => return NumericError.Long,
            }
        };
        const long: *c.PyObject = convert_fn(value) orelse return NumericError.Long;
        return fromObjectFast(.fromC(long));
    }

    /// Return the integer representation. Setup OverflowError and return
    /// NumericError when failed. Note that the underlying function uses 64
    /// bit, so the number that is too big will fail.
    pub fn toInt(self: *LongObject, T: type) NumericError!T {
        const int_info = @typeInfo(T).int;
        const convert_fn = blk: {
            if (int_info.signedness == .signed) {
                if (@sizeOf(c_long) == 8)
                    break :blk c.PyLong_AsLong
                else
                    break :blk c.PyLong_AsLongLong;
            } else {
                if (@sizeOf(c_long) == 8)
                    break :blk c.PyLong_AsUnsignedLong
                else
                    break :blk c.PyLong_AsUnsignedLongLong;
            }
        };
        const Int64: type = @Type(.{ .int = .{ .signedness = int_info.signedness, .bits = 64 } });
        const intvalue: Int64 = convert_fn(self.toObject().toC());
        if (@as(i64, @bitCast(intvalue)) == -1 and Err.occurred() != null) {
            return NumericError.Long;
        }
        if (int_info.bits < 64) {
            if (intvalue <= std.math.maxInt(T) and intvalue >= std.math.minInt(T)) {
                return @intCast(intvalue);
            } else {
                Err.setString(PyExc_OverflowError, "");
                return NumericError.Long;
            }
        } else {
            return intvalue;
        }
    }
};

pub extern var _Py_TrueStruct: LongObject;
pub extern var _Py_FalseStruct: LongObject;

/// Fake bool object type, PyLongObject under the hood. Should be
/// kept in sync with PyLongObject.
pub const BoolObject = extern struct {
    ob_base: Object,
    long_value: c._PyLongValue,

    pub const _PyLongValue = extern struct {
        lv_tag: usize,
        ob_digit: [1]u32,
    };

    /// Make the object an int if possible, otherwise set exception and return error.
    pub fn fromObject(object: *Object) TypeError!*BoolObject {
        if (isBool(object)) {
            return fromObjectFast(object);
        } else {
            Err.setString(PyExc_TypeError, "not a bool");
            return TypeError.PyType;
        }
    }

    /// Make the object an int without checking.
    pub fn fromObjectFast(object: *Object) TypeError!*BoolObject {
        return @fieldParentPtr("ob_base", object);
    }

    pub fn fromLong(long: *LongObject) *BoolObject {
        if (isBool(long)) {
            return @fieldParentPtr("ob_base", long);
        } else {
            Err.setString(PyExc_TypeError, "not a bool");
            return TypeError.PyType;
        }
    }

    // no toC because there is no PyBoolObject

    pub fn toObject(self: *BoolObject) *Object {
        return &self.ob_base;
    }

    pub fn toLong(self: *BoolObject) *LongObject {
        return @ptrCast(self);
    }

    pub fn isBool(obj: *Object) bool {
        return c.PyBool_Check(obj.toC()) != 0;
    }

    /// The Python True object. This object is immortal (python 3.12+).
    pub fn Py_True() *BoolObject {
        return @ptrCast(&_Py_TrueStruct);
    }

    /// The Python False object. This object is immortal (python 3.12+).
    pub fn Py_False() *BoolObject {
        return @ptrCast(&_Py_FalseStruct);
    }

    /// Returns a new reference.
    pub fn fromBool(v: bool) *BoolObject {
        if (v) {
            const t = Py_True();
            IncRef(t);
            return t;
        } else {
            const f = Py_False();
            IncRef(f);
            return f;
        }
    }

    pub fn toBool(self: *BoolObject) bool {
        const truthy: i32 = c.PyObject_IsTrue(self.toObject().toC());
        assert(truthy >= 0);
        return truthy > 0;
    }
};

/// Float object type, immutable
pub const FloatObject = extern struct {
    ob_base: Object,
    ob_fval: f64,

    /// Make the object a float if possible, otherwise set exception and return error.
    pub fn fromObject(object: *Object) TypeError!*FloatObject {
        if (isFloat(object)) {
            return fromObjectFast(object);
        } else {
            Err.setString(PyExc_TypeError, "not a float");
            return TypeError.PyType;
        }
    }

    /// Make the object a float without checking.
    pub fn fromObjectFast(object: *Object) *FloatObject {
        return @fieldParentPtr("ob_base", object);
    }

    pub fn toC(self: *FloatObject) *c.PyFloatObject {
        return @ptrCast(self);
    }

    pub fn toObject(self: *FloatObject) *Object {
        return &self.ob_base;
    }

    pub fn isFloat(obj: *Object) bool {
        return c.PyFloat_Check(obj.toC()) != 0;
    }

    /// Returns a new reference.
    pub fn fromf64(value: f64) NumericError!*FloatObject {
        const float = c.PyFloat_FromDouble(value) orelse return NumericError.Float;
        return fromObjectFast(.fromC(float));
    }

    pub fn tof64(self: *FloatObject) NumericError!f64 {
        const floatvalue: f64 = c.PyFloat_AsDouble(self.toObject().toC());
        if (floatvalue == -1 and Err.occurred() != null) {
            return NumericError.Float;
        }
        return floatvalue;
    }
};

/// Integer or float object type. Cannot convert from zig type.
pub const NumericObject = opaque {
    /// Make the object a float/int if possible, otherwise set exception and return error.
    pub fn fromObject(object: *Object) TypeError!*NumericObject {
        if (isFloat(object)) {
            return @ptrCast(object);
        } else if (isLong(object)) {
            return @ptrCast(object);
        } else {
            Err.setString(PyExc_TypeError, "not a float or int");
            return TypeError.PyType;
        }
    }

    pub fn isFloat(obj: *Object) bool {
        return c.PyFloat_Check(obj.toC()) != 0;
    }

    pub fn isLong(obj: *Object) bool {
        return c.PyLong_Check(obj.toC()) != 0;
    }

    pub fn toFloatObject(self: *NumericObject) TypeError!*FloatObject {
        return try FloatObject.fromObject(@ptrCast(self));
    }

    pub fn toFloatObjectFast(self: *NumericObject) *FloatObject {
        return FloatObject.fromObjectFast(@ptrCast(self));
    }

    pub fn toLongObject(self: *NumericObject) TypeError!*LongObject {
        return try LongObject.fromObject(@ptrCast(self));
    }

    pub fn toLongObjectFast(self: *NumericObject) *LongObject {
        return LongObject.fromObjectFast(@ptrCast(self));
    }
};

/// Unicode object, represent python normal string. Note: don't rely on the
/// layout, the actual layout might differ.
pub const UnicodeObject = extern struct {
    _base: PyCompactUnicodeObject,
    data: extern union {
        any: ?*anyopaque,
        latin1: [*c]u8,
        ucs2: [*c]u16,
        ucs4: [*c]u32,
    },

    pub const PyCompactUnicodeObject = extern struct {
        _base: PyASCIIObject,
        utf8_length: isize,
        utf8: [*c]u8,
    };

    pub const PyASCIIObject = extern struct {
        ob_base: Object,
        length: isize,
        hash: isize,
        state: packed struct(u32) {
            interned: u2,
            kind: u3,
            compact: u1,
            ascii: u1,
            statically_allocated: u1,
            _8: u24,
        },
    };

    /// Make the object a str if possible, otherwise set exception and return
    /// error.
    pub fn fromObject(object: *Object) TypeError!*UnicodeObject {
        if (isUnicode(object)) {
            return fromObjectFast(object);
        } else {
            Err.setString(PyExc_TypeError, "not a str");
            return TypeError.PyType;
        }
    }

    /// Make the object a str without checking.
    pub fn fromObjectFast(object: *Object) *UnicodeObject {
        const ascii: *PyASCIIObject = @fieldParentPtr("ob_base", object);
        const compact: *PyCompactUnicodeObject = @fieldParentPtr("_base", ascii);
        return @fieldParentPtr("_base", compact);
    }

    // no toC() because it is broken.

    pub fn toObject(self: *UnicodeObject) *Object {
        return &self._base._base.ob_base;
    }

    pub fn isUnicode(obj: *Object) bool {
        return c.PyUnicode_Check(obj.toC()) != 0;
    }

    /// Create a Unicode object from a UTF-8 encoded null-terminated char
    /// buffer str.
    ///
    /// Returns a new reference.
    pub fn fromString(str: [*:0]const u8) *UnicodeObject {
        // yes, this will not error
        const c_object: *c.PyObject = c.PyUnicode_FromString(str).?;
        return UnicodeObject.fromObjectFast(.fromC(c_object));
    }

    /// Turns unicode object into string. Setup PyExc_UnicodeError and return
    /// UnicodeError when failed.
    pub fn toOwnedSlice(self: *UnicodeObject, allocator: Allocator) (UnicodeError || MemoryError)![:0]u8 {
        var str_size: isize = undefined;
        const str_opt: ?[*:0]const u8 = c.PyUnicode_AsUTF8AndSize(self.toObject().toC(), &str_size);
        if (str_opt) |str| {
            return allocator.dupeZ(u8, str[0..@intCast(str_size)]) catch
                return Err.outOfMemory();
        } else {
            Err.setString(c.PyExc_UnicodeError, "");
            return UnicodeError.Unicode;
        }
    }
};

pub const ListObject = extern struct {
    ob_base: VarObject,
    ob_item: [*]*Object,
    allocated: isize,

    /// Make the object a list if possible, otherwise set exception and return error.
    pub fn fromObject(object: *Object) TypeError!*ListObject {
        if (isList(object)) {
            return fromObjectFast(object);
        } else {
            Err.setString(PyExc_TypeError, "not a list");
            return TypeError.PyType;
        }
    }

    /// Make the object a list without checking.
    pub fn fromObjectFast(object: *Object) *ListObject {
        const varobject: *VarObject = @fieldParentPtr("ob_base", object);
        return @fieldParentPtr("ob_base", varobject);
    }

    pub fn toC(self: *ListObject) *c.PyListObject {
        return @ptrCast(self);
    }

    pub fn toObject(self: *ListObject) *Object {
        return &self.ob_base.ob_base;
    }

    /// Return a new tuple object of size len, set exception and return error
    /// on failure. If len is greater than zero, the returned list object’s
    /// items are set to NULL.
    ///
    /// Returns a new reference.
    pub fn new(len: usize) MemoryError!*ListObject {
        if (len > std.math.maxInt(isize)) {
            Err.setString(PyExc_MemoryError, "len exceed max isize");
            return MemoryError.PyAlloc;
        }
        const obj_c: *c.PyObject = c.PyList_New(@intCast(len)) orelse return MemoryError.PyAlloc;
        return ListObject.fromObjectFast(.fromC(obj_c));
    }

    pub fn isList(object: *Object) bool {
        return c.PyList_Check(object.toC()) != 0;
    }

    pub fn getSize(self: *ListObject) usize {
        return @intCast(self.ob_base.ob_size);
    }

    /// Insert a reference to object obj at position idx of the tuple, set
    /// exception and return IndexError on failure.
    pub fn setItem(self: *ListObject, idx: isize, obj: *Object) IndexError!void {
        IncRef(obj); // c.PyList_SetItem steal reference
        const res: i32 = c.PyList_SetItem(self.toObject().toC(), idx, obj.toC());
        if (res < 0) {
            return IndexError.ListIndex;
        }
    }

    /// Get item by position. Set exception and return IndexError if idx is
    /// out of bound.
    pub fn getItem(self: *ListObject, idx: usize) IndexError!*Object {
        const item_opt: ?*c.PyObject = c.PyList_GetItem(self.toObject().toC(), @intCast(idx));
        if (item_opt) |item| {
            return Object.fromC(item);
        } else {
            return IndexError.ListIndex;
        }
    }

    /// Append the object item at the end of list list. Set exception
    /// and return MemoryError on failure.
    ///
    /// This function borrows a reference.
    pub fn append(self: *ListObject, obj: *Object) MemoryError!void {
        const result: i32 = c.PyList_Append(self.toObject().toC(), obj.toC());
        if (result < 0) {
            return MemoryError.PyAlloc;
        }
    }

    // Remove all items from list.
    pub fn clear(self: *ListObject) void {
        const result: i32 = c.PyList_SetSlice(self.toObject().toC(), 0, std.math.maxInt(isize), null);
        assert(result == 0);
    }

    /// Turns array of pointer of type T into list.
    pub fn fromSlice(T: type, slice: []*T) MemoryError!*ListObject {
        const list_obj: *ListObject = try ListObject.new(slice.len);
        for (slice, 0..) |item, idx| {
            list_obj.setItem(@intCast(idx), item.toObject()) catch unreachable;
        }
        return list_obj;
    }

    /// Turns list into array of pointer of type T.
    pub fn toOwnedSlice(self: *ListObject, allocator: Allocator, T: type) (TypeError || MemoryError)![]*T {
        if (comptime std.mem.eql(u8, @tagName(@typeInfo(T)), "pointer")) {
            @compileError(std.fmt.comptimePrint("T {} cannot be pointer", .{T}));
        }
        const size: usize = @intCast(self.ob_base.ob_size);
        const array: []*T = allocator.alloc(*T, size) catch
            return Err.outOfMemory();
        for (0..size) |idx| {
            const item_obj: *Object = self.getItem(idx) catch unreachable;
            array[idx] = try T.fromObject(item_obj);
        }
        return array;
    }
};

/// Tuple object type, immutable, field ob_item only means it takes at least
/// 1 space.
pub const TupleObject = extern struct {
    ob_base: VarObject,
    ob_item: [1]*Object,

    /// Make the object a tuple if possible, otherwise set exception and return error.
    pub fn fromObject(object: *Object) TypeError!*TupleObject {
        if (isTuple(object)) {
            return fromObjectFast(object);
        } else {
            Err.setString(PyExc_TypeError, "not a tuple");
            return TypeError.PyType;
        }
    }

    /// Make the object a tuple without checking.
    pub fn fromObjectFast(object: *Object) *TupleObject {
        const varobject: *VarObject = @fieldParentPtr("ob_base", object);
        return @fieldParentPtr("ob_base", varobject);
    }

    pub fn toC(self: *TupleObject) *c.PyTupleObject {
        return @ptrCast(self);
    }

    pub fn toObject(self: *TupleObject) *Object {
        return &self.ob_base.ob_base;
    }

    /// Return a new tuple object of size len, set exception and return error
    /// on failure.
    ///
    /// Returns a new reference.
    pub fn new(len: usize) MemoryError!*TupleObject {
        if (len > std.math.maxInt(isize)) {
            Err.setString(PyExc_MemoryError, "len exceed max isize");
            return MemoryError.PyAlloc;
        }
        const obj_c: *c.PyObject = c.PyTuple_New(@intCast(len)) orelse return MemoryError.PyAlloc;
        return TupleObject.fromObjectFast(.fromC(obj_c));
    }

    pub fn isTuple(obj: *Object) bool {
        return c.PyTuple_Check(obj.toC()) != 0;
    }

    pub fn getSize(self: *TupleObject) usize {
        return @intCast(self.ob_base.ob_size);
    }

    /// Insert a reference to object obj at position idx of the tuple, set
    /// exception and return IndexError on failure.
    pub fn setItem(self: *TupleObject, idx: isize, obj: *Object) IndexError!void {
        IncRef(obj); // c.PyTuple_SetItem steal reference
        const res: i32 = c.PyTuple_SetItem(self.toObject().toC(), idx, obj.toC());
        if (res < 0) {
            return IndexError.TupleIndex;
        }
    }

    /// Get item by position. Set exception and return IndexError if idx is
    /// out of bound.
    pub fn getItem(self: *TupleObject, idx: isize) IndexError!*Object {
        const item_opt: ?*c.PyObject = c.PyTuple_GetItem(self.toObject().toC(), @intCast(idx));
        if (item_opt) |item| {
            return Object.fromC(item);
        } else {
            return IndexError.TupleIndex;
        }
    }

    pub fn fromTuple(tuple: anytype) MemoryError!*TupleObject {
        const fields = @typeInfo(@TypeOf(tuple)).@"struct".fields;
        const tuple_obj: *TupleObject = try TupleObject.new(fields.len);
        inline for (fields, 0..) |field, idx| {
            const item = @field(tuple, field.name).toObject();
            tuple_obj.setItem(@intCast(idx), item) catch unreachable;
        }
        return tuple_obj;
    }

    /// Turns tuple into array.
    pub fn toOwnedSlice(self: *TupleObject, allocator: Allocator) Allocator.Error![]*Object {
        const size: usize = @intCast(self.ob_base.ob_size);
        const array: []*Object = allocator.alloc(*Object, size) catch
            return Err.outOfMemory();
        for (0..size) |idx| {
            array[idx] = self.getItem(idx).?;
        }
        return array;
    }
};

/// Dict object, represent python dict. Note: don't rely on the layout, the
/// actual layout might differ.
pub const DictObject = extern struct {
    ob_base: Object,
    ma_used: isize,
    ma_version_tag: u64,
    ma_keys: ?*c.PyDictKeysObject,
    ma_values: ?*c.PyDictValues,
    const PyDictKeysObject = struct {
        dk_refcnt: isize,
        dk_log2_size: u8,
        dk_log2_index_bytes: u8,
        dk_kind: u8,
        dk_version: u32,
        dk_usable: isize,
        dk_nentries: isize,
        dk_indices: [*c]c_char, // char is required to avoid strict aliasing.
    };
    const PyDictValues = struct {
        values: ?*[1]c.PyObject,
    };

    /// Make the object a tuple if possible, otherwise set exception and return error.
    pub fn fromObject(object: *Object) TypeError!*DictObject {
        if (isDict(object)) {
            return fromObjectFast(object);
        } else {
            Err.setString(PyExc_TypeError, "not a dict");
            return TypeError.PyType;
        }
    }

    /// Make the object a dict without checking.
    pub fn fromObjectFast(object: *Object) *TupleObject {
        return @fieldParentPtr("ob_base", object);
    }

    // no toC() because it is broken.

    pub fn toObject(self: *DictObject) *Object {
        return &self.ob_item;
    }

    pub fn isDict(obj: *Object) bool {
        return c.PyDict_Check(obj.toC()) != 0;
    }

    pub fn setItem(self: *DictObject, key: *Object, value: *Object) TypeError!void {
        // c.PyDict_SetItem doesn't steal reference
        const result: i32 = c.PyDict_SetItem(self.toObject().toC(), key.toC(), value.toC());
        if (result < 0) {
            return TypeError.PyType;
        }
    }

    /// Get item by key, doesn't increment reference count. Return null if not
    /// found. Return DictError if keys cannot hash or compare equal.
    pub fn getItem(self: *DictObject, key: *Object) DictError!?*Object {
        const item_opt: ?*c.PyObject = c.PyDict_GetItemWithError(self.toObject().toC(), key);
        if (item_opt) |item| {
            return Object.fromC(item);
        } else if (Err.occurred() != null) {
            return DictError.Dict;
        } else {
            return null;
        }
    }
};

// ========================================================================= //
// Python Error functions and types

/// Error helper functions
pub const Err = struct {
    /// Set the error indicator. To raise exception, return special value from the caller.
    pub fn setString(exception: *c.PyObject, string: [*:0]const u8) void {
        return c.PyErr_SetString(exception, string);
    }
    /// Set the error indicator. To raise exception, return special value from the caller.
    pub fn setObject(exception: *c.PyObject, object: *c.PyObject) void {
        return c.PyErr_SetObject(exception, object);
    }
    /// Clear the error indicator and print the traceback.
    pub fn print() void {
        return c.PyErr_Print();
    }
    /// Test whether the error indicator is set. If set, return the exception
    /// type. If not set, return null.
    pub fn occurred() ?*c.PyObject {
        return c.PyErr_Occurred() orelse return null;
    }
    /// Create custom exception object. The name argument must be the name of
    /// the new exception.
    ///
    /// Returns a new reference.
    pub fn NewException(name: [*:0]const u8, base: ?*Object, dict: ?*Object) ?*Object {
        return c.PyErr_NewException(name, base, dict) orelse return null;
    }
    /// Set the error indicator and return Allocator.Error.
    pub fn outOfMemory() Allocator.Error {
        c.PyErr_SetString(PyExc_MemoryError, "Allocator Error");
        return error.OutOfMemory;
    }
    /// Set the error indicator and return error.NullObject.
    pub fn NoneError(string: [*:0]const u8) TypeError {
        c.PyErr_SetString(PyExc_TypeError, string);
        return error.NullObject;
    }
};

// builtin error object
pub extern var PyExc_Exception: *c.PyObject;
pub extern var PyExc_ImportError: *c.PyObject;
pub extern var PyExc_TypeError: *c.PyObject;
pub extern var PyExc_AttributeError: *c.PyObject;
pub extern var PyExc_RuntimeError: *c.PyObject;
pub extern var PyExc_OSError: *c.PyObject;
pub extern var PyExc_KeyError: *c.PyObject;
pub extern var PyExc_IndexError: *c.PyObject;
pub extern var PyExc_OverflowError: *c.PyObject;
pub extern var PyExc_MemoryError: *c.PyObject;

// ========================================================================= //
// Module creation / declarations

pub const PyModuleDef = extern struct {
    m_base: PyModuleDef_Base = PyModuleDef_Base.init,
    m_name: [*:0]const u8,
    m_doc: ?[*:0]const u8,
    m_size: isize,
    m_methods: ?[*]PyMethodDef,
    m_slots: ?*c.PyModuleDef_Slot = null,
    m_traverse: c.traverseproc = null,
    m_clear: c.inquiry = null,
    m_free: ?*const fn (?*anyopaque) callconv(.c) void = null,

    pub fn init(
        name: [*:0]const u8,
        docs: ?[*:0]const u8,
        methods: ?[*]PyMethodDef,
        freefunc: ?*const fn (?*anyopaque) callconv(.c) void,
    ) PyModuleDef {
        return .{
            .m_base = PyModuleDef_Base.init,
            .m_name = name,
            .m_doc = docs,
            .m_size = -1,
            // PyMethodDef has same bit representation
            .m_methods = methods,
            .m_free = freefunc,
        };
    }

    fn toC(self: *PyModuleDef) *c.PyModuleDef {
        return @ptrCast(self);
    }

    /// Create a new module object. Set exception and return ModuleError on failure.
    pub fn create(module_def: *PyModuleDef) ModuleError!*Object {
        const module: *c.PyObject = c.PyModule_Create2(module_def.toC(), c.PYTHON_API_VERSION) orelse
            return ModuleError.ModuleDef;
        return Object.fromC(module);
    }
};

pub const PyModuleDef_Base = extern struct {
    ob_base: Object,
    m_init: ?*const fn () callconv(.c) ?[*]Object,
    m_index: isize,
    m_copy: ?[*]Object,

    pub const init: PyModuleDef_Base = .{
        .ob_base = Object.init(null),
        .m_init = null,
        .m_index = 0,
        .m_copy = null,
    };
};

/// Module namespace.
pub const Module = struct {
    /// Add an object to module as name. Return ModuleError on failure.
    pub fn AddObjectRef(mod: *Object, name: ?[*:0]const u8, object: *Object) ModuleError!void {
        const res: i32 = c.PyModule_AddObjectRef(mod.toC(), name, object.toC());
        if (res < 0) {
            return ModuleError.Module;
        }
    }
};

// ========================================================================= //
// Member creation/declarations
pub const PyMemberDef = extern struct {
    name: ?[*:0]const u8,
    type_: Type,
    offset: isize,
    flags: Flag,
    doc: ?[*:0]const u8,

    pub const Type = enum(i32) {
        /// i16 -> int
        SHORT = 0,
        /// i32 -> int
        INT = 1,
        /// c_long -> int
        LONG = 2,
        /// f32 -> float
        FLOAT = 3,
        /// f64 -> float
        DOUBLE = 4,
        /// [*:0]const u8 (pointer) -> str (read only)
        STRING = 5,
        /// Deprecated, use Py_T_OBJECT_EX instead
        _OBJECT = 6,
        /// u8 (0~127) -> str (length 1)
        CHAR = 7,
        /// i8 -> int
        BYTE = 8,
        /// u8 -> int
        UBYTE = 9,
        /// u16 -> int
        USHORT = 10,
        /// u32 -> int
        UINT = 11,
        /// c_ulong -> int
        ULONG = 12,
        /// [N:0]const u8 (stored directly) -> str (read only)
        STRING_INPLACE = 13,
        /// c_char (written as 0 or 1) -> bool
        BOOL = 14,
        /// PyObject -> object (can be deleted)
        OBJECT_EX = 16,
        /// i64 -> int
        LONGLONG = 17,
        /// u64 -> int
        ULONGLONG = 18,
        /// isize -> int
        PYSSIZET = 19,
        /// Deprecated. Value is always None.
        _NONE = 20,
    };

    pub const Flag = packed struct(i32) {
        READONLY: bool = false,
        // Emit an object.__getattr__ audit event before reading.
        AUDIT_READ: bool = false,
        /// Deprecated, no-op. Do not reuse the value.
        _WRITE_RESTRICTED: bool = false,
        RELATIVE_OFFSET: bool = false,
        _4: i28,
    };

    pub const Sentinal: PyMethodDef = .{
        .name = null,
        .type_ = 0,
        .offset = 0,
        .flags = 0,
        .doc = null,
    };
};

// ========================================================================= //
// Method creation / declarations

/// PyMethodDef with zig syntax. To use it, @ptrCast this into c.PyModuleDef.
pub const PyMethodDef = extern struct {
    ml_name: ?[*:0]const u8,
    ml_meth: PyCFunction,
    ml_flags: Flag,
    ml_doc: ?[*:0]const u8 = null,

    /// Method flag.
    pub const Flag = packed struct(i32) {
        VARARGS: bool = false,
        KEYWORDS: bool = false,
        NOARGS: bool = false,
        O: bool = false,
        CLASS: bool = false,
        STATIC: bool = false,
        COEXIST: bool = false,
        FASTCALL: bool = false,
        STACKLESS: bool = false,
        METHOD: bool = false,
        _10: i22 = 0,

        pub const default: Flag = .{ .VARARGS = true };
        pub const static: Flag = .{ .VARARGS = true, .STATIC = true };
    };

    pub const Sentinal: PyMethodDef = .{
        .ml_name = null,
        .ml_meth = null,
        .ml_flags = .{},
        .ml_doc = null,
    };
};
pub const PyCFunction = ?*const fn ([*c]c.PyObject, [*c]c.PyObject) callconv(.c) ?*c.PyObject;

pub const PyGetSetDef = extern struct {
    name: ?[*:0]const u8,
    get: ?*const fn (?*c.PyObject, ?*anyopaque) callconv(.c) ?*c.PyObject = null,
    set: ?*const fn (?*c.PyObject, [*c]c.PyObject, ?*anyopaque) callconv(.c) c_int = null,
    doc: ?[*:0]const u8 = null,
    closure: ?*anyopaque = null,

    pub const Sentinal: PyGetSetDef = .{
        .name = null,
        .get = null,
        .set = null,
        .doc = null,
        .closure = null,
    };

    pub fn toC(self: *PyGetSetDef) *c.PyGetSetDef {
        return @ptrCast(self);
    }
};

// ========================================================================= //
// Argument parsing and building

/// Parse args (tuple) into tuple of each type. T: output tuple type. The
/// type in T needs to implement public fromObject method (returns error union).
///
/// usage:
/// const val_1, const val_2 = try parseArgs(args, struct { *PyLongObject, *PyLongObject });
pub fn parseArgs(args_tuple: *TupleObject, T: type) ArgsError!T {
    const args_len: usize = args_tuple.getSize();
    const fields = @typeInfo(T).@"struct".fields;
    if (args_len != fields.len) {
        Err.setString(PyExc_TypeError, "incorrect argument count");
        return ArgsError.Argcount;
    }
    var out_tuple: T = undefined;
    inline for (fields, 0..) |field, idx| {
        const field_type = @typeInfo(field.type).pointer.child;
        const item_obj: *Object = try args_tuple.getItem(idx);
        @field(out_tuple, field.name) = try field_type.fromObject(item_obj);
    }
    return out_tuple;
}

/// Parse kwargs (dict) into tuple of each type. T: output tuple type. The
/// type in T needs to implement public fromObject method (returns error union).
///
/// usage:
/// const val_1, const val_2 = try parseKwargs(args, .{"val_1", "val_2"}, struct { *PyLongObject, *PyLongObject });
pub fn parseKwargs(args_dict: *DictObject, comptime keys: []const []const u8, T: type) KwargsError!T {
    const fields = @typeInfo(T).@"struct".fields;
    if (keys.len != fields.len) {
        @compileError("key length doesn't match output length");
    }
    var out_tuple: T = undefined;
    inline for (fields, keys) |field, key_str| {
        const key: UnicodeObject = UnicodeObject.fromString(key_str);
        const item_opt: ?*Object = try args_dict.getItem(key.toObject());
        if (item_opt) |item_obj| {
            const field_type = @typeInfo(field.type).pointer.child;
            @field(out_tuple, field.name) = try field_type.fromObject(item_obj);
        } else {
            Err.setString(PyExc_TypeError, "no such key in kwargs");
            return KwargsError.KeyNotFound;
        }
    }
    return out_tuple;
}

/// Packs tuple of each type into args (tuple).
///
/// Returns a new reference.
pub fn buildArgs(args: anytype) MemoryError!*TupleObject {
    return try TupleObject.fromTuple(args);
}

// ========================================================================= //
// Memory management

pub fn IncRef(obj: *Object) void {
    c.Py_IncRef(obj.toC());
}

pub fn DecRef(obj: *Object) void {
    c.Py_DecRef(obj.toC());
}

pub fn XDecRef(obj_opt: ?*Object) void {
    if (obj_opt) |obj| {
        c.Py_IncRef(obj.toC());
    }
}

// ========================================================================= //
// Python Object wrapper

/// Wraps a zig struct into python object.
///
/// params:
/// * Inner: Inner type.
/// * type_obj_: A subset of PyTypeObject.
/// * builtin_funcs: See `PyBuiltinExample`. Can be same as Inner.
///
/// returns:
/// ```
/// struct {
///     ob_base: PyObject,
///     inner: Inner,
///     pub var type_obj: PyTypeObject;
///     pub fn fromObject(obj: *Object) TypeError!*Self {
///         ...
///     }
///     pub fn toObject(self: *Self) *Object {
///         ...
///     }
/// }
/// ```
///
/// To use outer type, use `@fieldParentPtr("inner", self)`
///
pub fn WrapObject(
    Inner: type,
    type_obj_: TypeObjectBasic,
    builtin_funcs: anytype,
) type {
    return struct {
        ob_base: Object,
        inner: Inner,

        const _vtable = builtin_funcs;

        const type_obj_const: TypeObject = blk: {
            var type_obj_tmp: TypeObject = .{
                .ob_base = VarObject.init(null, 0),
                .tp_name = type_obj_.tp_name,
                .tp_doc = type_obj_.tp_doc,
                .tp_basicsize = @sizeOf(Self),
                .tp_itemsize = 0,
                .tp_flags = type_obj_.tp_flags,
                .tp_members = type_obj_.tp_members,
            };
            if (@hasDecl(_vtable, "py_new")) {
                type_obj_tmp.tp_new = struct {
                    pub fn py_new(py_type_c: ?*c.PyTypeObject, _args_opt: ?*c.PyObject, _kwargs_opt: ?*c.PyObject) callconv(.C) ?*c.PyObject {
                        _ = _args_opt;
                        _ = _kwargs_opt;
                        const self_obj: *Object = TypeObject.fromC(py_type_c.?).alloc() catch return null;
                        const self: *Self = Self.fromObject(self_obj) catch return null;
                        _vtable.py_new(&self.inner);
                        return self.toObject().toC();
                    }
                }.py_new;
            } else {
                type_obj_tmp.tp_new = struct {
                    pub fn py_new(py_type_c: ?*c.PyTypeObject, _args_opt: ?*c.PyObject, _kwargs_opt: ?*c.PyObject) callconv(.C) ?*c.PyObject {
                        _ = _args_opt;
                        _ = _kwargs_opt;
                        const self_obj: *Object = TypeObject.fromC(py_type_c.?).alloc() catch return null;
                        return self_obj.toC();
                    }
                }.py_new;
            }
            if (@hasDecl(_vtable, "py_init")) {
                const params = @typeInfo(@TypeOf(_vtable.py_init)).@"fn".params;
                const ArgsType = params[1].type.?;
                type_obj_tmp.tp_init = struct {
                    pub fn py_init(self_opt: ?*c.PyObject, args_opt: ?*c.PyObject, _kwargs_null: ?*c.PyObject) callconv(.C) c_int {
                        const self: *Self = Self.fromObject(.fromC(self_opt.?)) catch return -1;
                        const args_obj: *TupleObject = TupleObject.fromObject(.fromC(args_opt.?)) catch return -1;
                        const args: ArgsType = parseArgs(args_obj, ArgsType) catch return -1;
                        if (_kwargs_null != null) {
                            @branchHint(.unlikely);
                            Err.setString(PyExc_TypeError, "kwargs is not allowed");
                            return -1;
                        }
                        _vtable.py_init(&self.inner, args) catch return -1;
                        return 0;
                    }
                }.py_init;
            }
            if (@hasDecl(_vtable, "py_dealloc")) {
                type_obj_tmp.tp_dealloc = struct {
                    pub fn py_dealloc(self_opt: ?*c.PyObject) callconv(.C) void {
                        const self: *Self = Self.fromObject(.fromC(self_opt.?)) catch return;
                        _vtable.py_dealloc(&self.inner);
                        self.ob_base.ob_type.?.tp_free.?(self.toObject().toC());
                    }
                }.py_dealloc;
            }
            if (@hasDecl(_vtable, "py_getset")) {
                const structinfo = @typeInfo(@TypeOf(_vtable.py_getset)).@"struct";
                const fields = structinfo.fields;
                var py_getsetdef_list: [fields.len + 1]PyGetSetDef = .{PyGetSetDef.Sentinal} ** (fields.len + 1);
                for (fields, 0..) |field, idx| {
                    // getsetdef_list has one more element (sentinel)
                    const py_getsetdef: *PyGetSetDef = &py_getsetdef_list[idx];
                    const getsetdef = @field(_vtable.py_getset, field.name);
                    const GetSetDef = @TypeOf(getsetdef);
                    py_getsetdef.name = getsetdef.name;
                    if (@hasField(GetSetDef, "doc")) {
                        py_getsetdef.doc = getsetdef.doc;
                    }
                    if (@hasField(GetSetDef, "get")) {
                        const ReturnErrorUnion = @typeInfo(@TypeOf(getsetdef.get)).@"fn".return_type.?;
                        const ReturnValue = @typeInfo(ReturnErrorUnion).error_union.payload;
                        py_getsetdef.get = struct {
                            pub fn py_get(self_c: ?*c.PyObject, _closure: ?*anyopaque) callconv(.c) ?*c.PyObject {
                                _ = _closure;
                                const self: *Self = Self.fromObject(.fromC(self_c.?)) catch return null;
                                const ret: ReturnValue = getsetdef.get(&self.inner) catch return null;
                                return ret.toObject().toC();
                            }
                        }.py_get;
                    }
                    if (@hasField(GetSetDef, "set")) {
                        const ValuePtr = @typeInfo(@TypeOf(getsetdef.set)).@"fn".params[1].type.?;
                        const ValueType = @typeInfo(ValuePtr).pointer.child;
                        py_getsetdef.set = struct {
                            pub fn py_set(self_c: ?*c.PyObject, value_opt: ?*c.PyObject, _closure: ?*anyopaque) callconv(.c) i32 {
                                _ = _closure;
                                const self: *Self = Self.fromObject(.fromC(self_c.?)) catch return -1;
                                if (value_opt) |value_c| {
                                    const value: *ValueType = ValueType.fromObject(.fromC(value_c)) catch return -1;
                                    getsetdef.set(&self.inner, value) catch return -1;
                                    return 0;
                                } else {
                                    Err.setString(PyExc_AttributeError, "delete the attribute is not supported");
                                    return -1;
                                }
                            }
                        }.py_set;
                    }
                }
                const py_getsetdef_list_const = py_getsetdef_list;
                type_obj_tmp.tp_getset = @constCast(@ptrCast(&py_getsetdef_list_const));
            }
            if (@hasDecl(_vtable, "py_methods")) {
                const structinfo = @typeInfo(@TypeOf(_vtable.py_methods)).@"struct";
                const fields = structinfo.fields;
                var py_methoddef_list: [fields.len + 1]PyMethodDef = .{PyMethodDef.Sentinal} ** (fields.len + 1);
                for (fields, 0..) |field, idx| {
                    // methoddef_list has one more element (sentinel)
                    const py_methoddef: *PyMethodDef = &py_methoddef_list[idx];
                    const methoddef = @field(_vtable.py_methods, field.name);
                    const MethodDef = @TypeOf(methoddef);
                    py_methoddef.ml_name = methoddef.ml_name;
                    py_methoddef.ml_flags = methoddef.ml_flags;
                    if (@hasField(MethodDef, "ml_doc")) {
                        py_methoddef.ml_doc = methoddef.ml_doc;
                    }
                    const params = @typeInfo(@TypeOf(methoddef.ml_meth)).@"fn".params;
                    if (py_methoddef.ml_flags == PyMethodDef.Flag.default) {
                        const ArgsType = params[1].type.?;
                        py_methoddef.ml_meth = struct {
                            pub fn py_method(self_opt: ?*c.PyObject, args_opt: ?*c.PyObject) callconv(.C) ?*c.PyObject {
                                const self: *Self = Self.fromObject(.fromC(self_opt.?)) catch return null;
                                const args_obj: *TupleObject = TupleObject.fromObject(.fromC(args_opt.?)) catch return null;
                                const args: ArgsType = parseArgs(args_obj, ArgsType) catch
                                    return null;
                                const obj: *Object = methoddef.ml_meth(&self.inner, args) catch return null;
                                return obj.toC();
                            }
                        }.py_method;
                    } else if (py_methoddef.ml_flags == PyMethodDef.Flag.static) {
                        const ArgsType = params[0].type.?;
                        py_methoddef.ml_meth = struct {
                            pub fn py_method(_self_null: ?*c.PyObject, args_opt: ?*c.PyObject) callconv(.C) ?*c.PyObject {
                                if (_self_null != null) {
                                    @branchHint(.unlikely);
                                    Err.setString(PyExc_TypeError, "self is not null");
                                    return null;
                                }
                                const args_obj: *TupleObject = TupleObject.fromObject(.fromC(args_opt.?)) catch return null;
                                const args: ArgsType = parseArgs(args_obj, ArgsType) catch return null;
                                const obj: *Object = methoddef.ml_meth(args) catch return null;
                                return obj.toC();
                            }
                        }.py_method;
                    } else {
                        @compileError("ml_flags not supported");
                    }
                }
                const py_methoddef_list_const = py_methoddef_list;
                type_obj_tmp.tp_methods = @constCast(@ptrCast(&py_methoddef_list_const));
            }
            break :blk type_obj_tmp;
        };

        pub var type_obj: TypeObject = type_obj_const;

        pub fn fromObject(obj: *Object) TypeError!*Self {
            if (default_isType(obj, type_obj)) {
                return @fieldParentPtr("ob_base", obj);
            } else {
                Err.setString(PyExc_TypeError, "");
                return TypeError.PyType;
            }
        }

        pub fn toObject(self: *Self) *Object {
            return &self.ob_base;
        }

        const Self = @This();
    };
}

pub const TypeObjectBasic = struct {
    tp_name: ?[*:0]const u8,
    tp_doc: ?[*:0]const u8 = null,
    tp_flags: TypeObject.Flags = .DEFAULT,
    tp_members: ?[*]c.PyMemberDef = null,
};

/// Example builtin functions.
pub const PyBuiltinExample = struct {

    // Change Self based on the usage. Self corresponds to Inner in WrapObject.
    const Self = PyBuiltinExample;

    /// Used in tp_new or __new__. Default initialize variable. This function should not
    /// contain complex logic. This function cannot fail.
    pub fn py_new(self: *Self) void {
        _ = self;
    }
    /// Used in tp_init or __init__. Initialize or reinitialize variable.
    pub fn py_init(self: *Self, args: struct { *LongObject }) !void {
        _ = self;
        _ = args;
    }

    /// Used in tp_dealloc or (destruct object). This function cannot fail.
    pub fn py_dealloc(self: *Self) void {
        _ = self;
    }

    /// Used in tp_getset or (getattr/setattr). Structured as anonymous tuple
    /// of anonymous struct. Every fields except name are optional.
    pub const py_getset = .{
        .{
            .name = "val",
            .get = get_val,
            .set = set_val,
            .doc = null,
            .closure = null, // not functional
        },
    };

    /// Should return new reference on success or error on failure.
    fn get_val(self: *Self) !*LongObject {
        _ = self;
        return TypeError.PyType;
    }
    fn set_val(self: *Self, val: *LongObject) !void {
        _ = self;
        _ = val;
    }

    /// Used in tp_methods. Structured as anonymous tuple of anonymous struct.
    pub const py_methods = .{
        .{
            .ml_name = "foo",
            .ml_meth = foo,
            .ml_flags = PyMethodDef.Flag{ .VARARGS = true },
            .ml_doc = null,
        },
    };
    fn foo(self: *Self) !*Object {
        _ = self;
        IncRef(Py_None());
        return Py_None();
    }
};

// ========================================================================= //
// Import / Call

/// Returns a new reference.
pub fn import(name: [*:0]const u8) ImportError!*Object {
    const name_py = UnicodeObject.fromString(name);
    defer DecRef(name_py.toObject());
    const c_module = c.PyImport_Import(name_py.toObject().toC()) orelse return ImportError.Import;
    return Object.fromC(c_module);
}

/// Returns a new reference.
pub fn getAttrString(obj: *Object, attr_name: [*:0]const u8) AttributeError!*Object {
    const attr_name_py = UnicodeObject.fromString(attr_name);
    defer DecRef(attr_name_py.toObject());
    const c_attr = c.PyObject_GetAttr(obj.toC(), attr_name_py.toObject().toC()) orelse return AttributeError.Attribute;
    return Object.fromC(c_attr);
}

/// Returns a new reference.
pub fn call(callable: *Object, args: anytype) CallError!*Object {
    const args_obj: *TupleObject = try TupleObject.fromTuple(args);
    defer DecRef(args_obj.toObject());
    return try callObject(callable, args_obj);
}

/// Returns a new reference.
pub fn callNoArgs(callable: *Object) CallError!*Object {
    const _args: *TupleObject = try TupleObject.new(0);
    defer DecRef(_args.toObject());
    return try callObject(callable, _args);
}

/// Equivilent to `AnyObject.name(*args)`.
///
/// Returns a new reference.
pub fn callStaticMethod(AnyObject: *Object, name: [*:0]const u8, args: anytype) CallError!*Object {
    const args_obj: *TupleObject = try TupleObject.fromTuple(args);
    defer DecRef(args_obj.toObject());
    const method: *Object = try getAttrString(AnyObject, name);
    defer DecRef(method);
    return try callObject(method, args_obj);
}

/// Equivilent to `obj.name(*args)` or `AnyObject.name(obj, *args)`.
///
/// Returns a new reference.
pub fn callMethod(obj: *Object, name: [*:0]const u8, args: anytype) CallError!*Object {
    const method: *Object = try getAttrString(obj, name);
    defer DecRef(method);
    // obj is not in args
    const args_obj: *TupleObject = try TupleObject.fromTuple(args);
    defer DecRef(args_obj.toObject());
    return try callObject(method, args_obj);
}

/// Returns a new reference.
pub fn callObject(callable: *Object, args: *TupleObject) CallError!*Object {
    const result_opt_c: ?*c.PyObject = c.PyObject_Call(
        callable.toC(),
        args.toObject().toC(),
        null,
    );
    if (result_opt_c) |result_opt| {
        return Object.fromC(result_opt);
    } else {
        @branchHint(.unlikely);
        const pyerr = Err.occurred();
        assert(pyerr != null);
        return CallError.Call;
    }
}

/// Calls python `__new__` with no argument. To fully initialize an object, use
/// callNoArgs(type_obj.toObject()) or callObject(type_obj.toObject(), args)
pub fn callNew(T: type, type_obj: *TypeObject) MemoryTypeError!*T {
    const new_args: *TupleObject = try TupleObject.new(0);
    const obj_c: *c.PyObject = type_obj.tp_new.?(type_obj.toC(), new_args.toObject().toC(), null);
    const obj: *T = try T.fromObject(.fromC(obj_c));
    DecRef(new_args.toObject());
    return obj;
}

// ========================================================================= //
// Misc helper

/// Returns a new reference.
pub fn listFromNdarray(ndarray: anytype) ListConversionError!*ListObject {
    const list_obj = try ListObject.new(ndarray.len);
    try listFromNdarrayInner(ndarray, list_obj);
    return list_obj;
}

fn listFromNdarrayInner(ndarray: anytype, outlist: *ListObject) ListConversionError!void {
    const Child = switch (@typeInfo(@TypeOf(ndarray))) {
        .array => |array| array.child,
        .pointer => |pointer| pointer.child,
        else => @compileError("invalid child type"),
    };
    for (ndarray, 0..) |item, idx| {
        const item_obj: *Object = blk: switch (@typeInfo(Child)) {
            .int => {
                const _item: *LongObject = try .fromInt(Child, item);
                break :blk _item.toObject();
            },
            .float => {
                const _item: *FloatObject = try .fromf64(item);
                break :blk _item.toObject();
            },
            .array, .pointer => {
                const _list: *ListObject = try .new(item.len);
                try listFromNdarrayInner(item, _list);
                break :blk _list.toObject();
            },
            else => @compileError("type not allowed"),
        };
        defer DecRef(item_obj);
        outlist.setItem(@intCast(idx), item_obj) catch unreachable;
    }
}

pub fn listFromStrArray(str_array: anytype) ListConversionError!*ListObject {
    const list_obj = try ListObject.new(str_array.len);
    try listFromStrArrayInner(str_array, list_obj);
    return list_obj;
}

fn listFromStrArrayInner(str_array: anytype, outlist: *ListObject) ListConversionError!void {
    const Child = switch (@typeInfo(@TypeOf(str_array))) {
        .array => |array| array.child,
        .pointer => |pointer| pointer.child,
        else => @compileError("invalid child type"),
    };
    const Gchild = switch (@typeInfo(Child)) {
        .array => |array| array.child,
        .pointer => |pointer| pointer.child,
        else => @compileError("invalid grand child type"),
    };
    for (str_array, 0..) |item, idx| {
        const item_obj: *Object = blk: switch (@typeInfo(Gchild)) {
            .int => {
                const _item: *UnicodeObject = .fromString(item);
                break :blk _item.toObject();
            },
            .array, .pointer => {
                const _list: *ListObject = try .new(item.len);
                try listFromStrArrayInner(item, _list);
                break :blk _list.toObject();
            },
            else => @compileError("type not allowed"),
        };
        defer DecRef(item_obj);
        outlist.setItem(@intCast(idx), item_obj) catch unreachable;
    }
}

pub fn ndarrayFromList(allocator: Allocator, list: *ListObject, T: type) ListConversionError!T {
    const Child = @typeInfo(T).pointer.child;
    const outarray = allocator.alloc(Child, list.getSize()) catch
        return Err.outOfMemory();
    try ndarrayFromListAlloc(allocator, list, outarray);
    return outarray;
}

fn ndarrayFromListAlloc(allocator: Allocator, list_obj: *ListObject, outarray: anytype) ListConversionError!void {
    const Child = @typeInfo(@TypeOf(outarray)).pointer.child;
    const size: usize = @intCast(list_obj.ob_base.ob_size);
    assert(size == outarray.len);
    switch (@typeInfo(Child)) {
        .int => {
            for (0..size) |idx| {
                const item_obj: *Object = list_obj.getItem(idx) catch unreachable;
                const item_long: *LongObject = try .fromObject(item_obj);
                outarray[idx] = try item_long.toInt(Child);
            }
        },
        .float => {
            for (0..size) |idx| {
                const item_obj: *Object = list_obj.getItem(idx) catch unreachable;
                const item_float: *FloatObject = try .fromObject(item_obj);
                outarray[idx] = try item_float.tof64();
            }
        },
        .pointer => {
            const list: []*ListObject = try list_obj.toOwnedSlice(allocator, ListObject);
            defer allocator.free(list);
            for (list, outarray) |item, *out_item| {
                const Gchild = @typeInfo(Child).pointer.child;
                out_item.* = allocator.alloc(Gchild, item.getSize()) catch
                    return Err.outOfMemory();
                try ndarrayFromListAlloc(allocator, item, out_item.*);
            }
        },
        else => @compileError("type not allowed"),
    }
}

/// Asserts outarray.len == list_obj.getSize().
pub fn ndarrayFromListFill(list_obj: *ListObject, outarray: anytype) ListConversionError!void {
    const Child = @typeInfo(@TypeOf(outarray)).pointer.child;
    const size: usize = @intCast(list_obj.ob_base.ob_size);
    assert(size == outarray.len);
    switch (@typeInfo(Child)) {
        .int => {
            for (0..size) |idx| {
                const item_obj: *Object = list_obj.getItem(idx) catch unreachable;
                const item_long: *LongObject = try .fromObject(item_obj);
                outarray[idx] = try item_long.toInt(Child);
            }
        },
        .float => {
            for (0..size) |idx| {
                const item_obj: *Object = list_obj.getItem(idx) catch unreachable;
                const item_float: *FloatObject = try .fromObject(item_obj);
                outarray[idx] = try item_float.tof64();
            }
        },
        .pointer => {
            for (0..size) |idx| {
                const item_obj: *Object = list_obj.getItem(idx) catch unreachable;
                const item_list: *ListObject = try .fromObject(item_obj);
                try ndarrayFromListFill(item_list, outarray[idx]);
            }
        },
        else => @compileError("type not allowed"),
    }
}

pub fn strArrayFromList(allocator: Allocator, list: *ListObject, T: type) ListConversionError!T {
    const Child = @typeInfo(T).pointer.child;
    const outarray = allocator.alloc(Child, list.getSize()) catch
        return Err.outOfMemory();
    try strArrayFromListInner(allocator, list, T, outarray);
    return outarray;
}

fn strArrayFromListInner(allocator: Allocator, list_obj: *ListObject, T: type, outarray: T) ListConversionError!void {
    const Child = @typeInfo(T).pointer.child;
    const GChild = @typeInfo(Child).pointer.child;
    switch (@typeInfo(GChild)) {
        .int => {
            const list: []*UnicodeObject = try list_obj.toOwnedSlice(allocator, UnicodeObject);
            defer allocator.free(list);
            for (list, outarray) |item, *out_item| {
                out_item.* = try item.toOwnedSlice(allocator);
            }
        },
        .pointer => {
            const list: []*ListObject = try list_obj.toOwnedSlice(allocator, ListObject);
            defer allocator.free(list);
            for (list, outarray) |item, *out_item| {
                const Gchild = @typeInfo(Child).pointer.child;
                out_item.* = allocator.alloc(Gchild, item.getSize()) catch
                    return Err.outOfMemory();
                try strArrayFromListInner(allocator, item, Child, out_item.*);
            }
        },
        else => @compileError("type not allowed"),
    }
}

pub fn eql_cstr(a: [*:0]const u8, b: [*:0]const u8) bool {
    return std.mem.orderZ(u8, a, b) == .eq;
}

/// Check of `obj` is of type `type_obj` by comparing `tp_name`.
pub fn default_isType(obj: *Object, type_obj: TypeObject) bool {
    return eql_cstr(obj.ob_type.?.tp_name.?, type_obj.tp_name.?);
}

// ========================================================================= //
// compile time stuff

fn assertmessage(comptime ok: bool, comptime message: []const u8) void {
    if (!ok) {
        @compileLog("{s}", message);
        unreachable;
    }
}

fn assertmessageZ(comptime ok: bool, comptime messagez: [*:0]const u8) void {
    const message: []const u8 = std.mem.span(messagez);
    assertmessage(ok, message);
}

// ========================================================================= //
// Zig error set

/// Generic memory related error.
pub const MemoryError = error{PyAlloc} || Allocator.Error;
/// Python type casting error.
pub const TypeError = error{ PyType, NullObject };
/// Python attribute related error
pub const AttributeError = error{Attribute};
/// Any error that python call() returns
pub const CallError = MemoryError || AttributeError || error{Call};
/// Python float/int related error.
pub const NumericError = error{ Long, Float };
/// Python str related error.
pub const UnicodeError = error{Unicode};
/// Python list related error.
pub const ListError = error{List};
/// Python tuple related error.
pub const TupleError = error{Tuple};
/// Python dict related error.
pub const DictError = error{ Dict, KeyNotFound };
/// Python index error.
pub const IndexError = error{ ListIndex, TupleIndex, DictIndex };
/// Module creation related error.
pub const ModuleError = TypeError || error{ ModuleDef, Module };
/// Import related error.
pub const ImportError = error{Import};
/// Argument related error.
pub const ArgsError = IndexError || TypeError || error{Argcount};
/// Argument related error.
pub const KwargsError = DictError;
/// No error, for function compatibility.
pub const NoError = error{};
/// Generic memory related error and Python type casting error.
pub const MemoryTypeError = MemoryError || TypeError;
/// List conversion related error.
pub const ListConversionError = NumericError || UnicodeError || MemoryError || TypeError;

// ========================================================================= //
//

/// Leftover python declaration.
pub const c = @cImport({
    @cDefine("PY_SSIZE_T_CLEAN", {});
    @cInclude("python.h");
});

// ========================================================================= //
// Imports

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
