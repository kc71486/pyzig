## 0.6.0

### breaking changes
* `call` and its variant now accepts `[]*const Object` instead of tuple or struct.
  * Migration guide: `call(obj, .{arg1, arg2})` -> `call(obj, &.{arg1, arg2})`,  
  `callKwargs(obj, .{arg1, arg2}, .{.kw1 = arg3})` -> `callKwargs(obj, &.{arg1, arg2}, .{.kw1 = arg3})`.
  * `parseArgs` unchanged, it still accepts tuple/struct of any Object compatible type.

### new stuffs
* Add `Builtin.list`.
* Add `DictObject.setItemString`.
* Add `TupleObject.fromSlice`.

### changes
* It is now compatible with 0.16.0.
* `ListObject.fromSlice` now accepts const slice.

### bug fixes
* Add various `defer` for cleanup.

## 0.5.0

### breaking changes
* Change various type name:
  * `PyModuleDef` -> `ModuleDef`
  * `PyModuleDef_Base` -> `ModuleDefBase`
  * `PyMemberDef` -> `MemberDef`
  * `PyMethodDef` -> `MethodDef`
  * `PyGetSetDef` -> `GetSetDef`

## 0.4.0

### breaking changes
* Change `ListObject.fromSlice` to only accept object slice, add `ListObject.fromSliceT` for original
purpose.
* Change `TupleObject.fromTuple` to only accept object slice, add `TupleObject.fromTupleT` for original
purpose.
* `call` and its variant now only accepts `Object` in its tuple or struct.

### removed stuffs
* Remove `callNoArgs`.
  * `call(obj, .{})` already accomplishes this, and there is no function duplication issues.
* Remove `ndarrayFromListFill`
  * list size needs to be determined at runtime, in which `ndarrayFromList` does a better job.

### new stuffs
* Add `Iterator`.
* Add `TupleObject.toTuple`.

### changes
* Change various argument name: `allocator` -> `gpa`.

### bug fixes
* Add various `defer` and `errdefer` for cleanup.

## 0.3.1

### bug fixes
* Fix `BoolObject.fromBool`.

### changes
* `Builtin.print` now uses better global allocator.

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
