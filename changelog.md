## 0.3.0

### Err namespace reformation
* Add `Standard` namespace, holding various standard exception.
* Change all functions in Err namespace to accept and return `*Object` instead of `*c.pyObject`.
* Remove all global `PyExc_*` declaration, move it into `Err.Standard` namespace and make it a function.
* Add `displayException`, and fix `NewException`

### breaking changes
* Change `PyCFunction` definition `?*const fn ([*c]c.PyObject, [*c]c.PyObject) callconv(.c) ?*c.PyObject` ->
`*const fn (*c.PyObject, *c.PyObject) callconv(.c) ?*c.PyObject`, PyMethodDef remain unchanged.
* Change `Err.NoneError([*:0]const u8)` into `Err.noneError([*:0]const u8)`.
* Change `PrintError` into `BuiltinError`
  * `PrintError.Print` -> `BuiltinError.Print`.

### deprecations
* add `None()`, deprecate `Py_None()`

### new stuffs
* add `wrapPyCFunctionDefault`.
* add `fromObjectExact` and `isDictExact` in DictObject.
* add `Err.customError([*:0]const u8)` and CustomError.
* add `Interpreter` and `InterpreterError`.
* add more functions in `Builtin` namespace.

### changes
* change `@cimport` into `b.addTranslateC` and `c` module, make `py` module able to use debug build.
* `py` module no longer links libc.

### bug fixes
* fix `DictObject.fromObject` discription.
* fix `DictObject.fromObjectFast` return type.
* make `DictObject.toObject` and `DictObject.getItem` work.
