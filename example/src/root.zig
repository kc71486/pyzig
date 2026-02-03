pub const Custom = struct {
    value: f64,

    pub const type_obj: py.TypeObjectBasic = .{
        .tp_name = "root.Custon",
        .tp_flags = .DEFAULT,
    };

    pub const py_getset = .{
        .{ .name = "value", .get = py_get_value },
    };

    pub fn py_init(self: *Custom, args: struct { value_obj: *py.FloatObject }) !void {
        const value: f64 = try args.value_obj.tof64();
        self.* = .{
            .value = value,
        };
    }

    fn py_get_value(self: *Custom) !*py.FloatObject {
        return try py.FloatObject.fromf64(self.value);
    }
};

pub const CustomObject = py.WrapObject(Custom, Custom.type_obj, Custom);

pub var module_def: py.ModuleDef = .init("history", null, &module_methods, null);
pub var module_methods: [1]py.MethodDef = .{
    py.MethodDef.Sentinal,
};

pub export fn PyInit_root() callconv(.c) ?*py.c.PyObject {
    CustomObject.type_obj.ready() catch return null;
    const module: *py.Object = module_def.create() catch return null;
    py.Module.AddObjectRef(module, "Custom", CustomObject.type_obj.toObject()) catch {
        py.DecRef(module);
        return null;
    };
    return module.toC();
}

const std = @import("std");
const py = @import("py");
