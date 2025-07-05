## pyzig

### disclaimer

* This only works with python 3.12.x release version, any other version are not guaranteed to match.
* This package make use of immortal object, and python < 3.12 will not clean up these object on exit.
This is not memory leak (they are singleton and have static lifetime in python < 3.12).

### features

* Wraps some basic python functions/pyobjects.
* Static link python library (release version).

### usage

Fetch this repository and add
```
const pyzig = b.dependency("pyzig", .{});
const module_py = pyzig.module("py");
```
to the build.zig.
