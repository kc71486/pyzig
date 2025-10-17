## 0.3.0

### breaking changes
* Change `PyCFunction` definition `?*const fn ([*c]c.PyObject, [*c]c.PyObject) callconv(.c) ?*c.PyObject` ->
`*const fn (*c.PyObject, *c.PyObject) callconv(.c) ?*c.PyObject`, PyMethodDef remain unchanged.
* Change `Err.NoneError([*:0]const u8)` into `Err.noneError([*:0]const u8)`

### deprecations
* add `None()`, deprecate `Py_None()`

### new stuffs
* add `wrapPyCFunctionDefault`.
* add `fromObjectExact` and `isDictExact` in DictObject.
* add `Err.customError([*:0]const u8)` and CustomError.
* add `Interpreter` and `InterpreterError`.

### changes
* change `@cimport` into `b.addTranslateC` and `c` module, make `py` module able to use debug build.
* `py` module no longer links libc.

### bug fixes
* fix `DictObject.fromObject` discription.
* fix `DictObject.fromObjectFast` return type.
* make `DictObject.toObject` and `DictObject.getItem` work.
