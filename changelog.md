## 3.0

### new stuff
* add `wrapPyCFunctionDefault`

### changed sttuff
* add `None()`, deprecate `Py_None()`
* change `@cimport` into `b.addTranslateC` and `c` module, make `py` module able to use debug build.
* `py` module no longer links libc.

### breaking
* Change `PyCFunction` definition `?*const fn ([*c]c.PyObject, [*c]c.PyObject) callconv(.c) ?*c.PyObject` ->
`*const fn (*c.PyObject, *c.PyObject) callconv(.c) ?*c.PyObject`, PyMethodDef remain unchanged.
