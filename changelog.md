## 3.0

### new stuff
* add `wrapPyCFunctionDefault`

### changed sttuff
* add `None()`, deprecate `Py_None()`

### breaking
* Change `PyCFunction` definition `?*const fn ([*c]c.PyObject, [*c]c.PyObject) callconv(.c) ?*c.PyObject` ->
`*const fn (*c.PyObject, *c.PyObject) callconv(.c) ?*c.PyObject`, PyMethodDef remain unchanged.
