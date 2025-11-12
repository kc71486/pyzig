## 0.3.1

### bug fixes
* Fix `BoolObject.fromBool`.

## 0.3.0

### minimum version change
* The minimum version is now 0.15.1, although most functions still work well in 0.14.1.

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
* Add `None()`, deprecate `Py_None()`.

### new stuffs
* Add `wrapPyCFunctionDefault`.
* Add `fromObjectExact` and `isDictExact` in DictObject.
* Add `Err.customError([*:0]const u8)` and CustomError.
* Add `Interpreter` and `InterpreterError`.
* Add more functions in `Builtin` namespace.
* Add more functions in `DictObject`.
* Add kwargs variants to `call`, `callObject`, and `callMethod`.

### changes
* Change `@cimport` into `b.addTranslateC` and `c` module, make `py` module able to use debug build.
* `py` module no longer links libc.
* Change all `callconv(.C)` -> `callconv(.c)`.

### bug fixes
* Fix `DictObject.fromObject` discription.
* Fix `DictObject.fromObjectFast` return type.
* Make `DictObject.toObject` and `DictObject.getItem` work.
* Make `Builtin.print` work (by using zig print).
