## pyzig

### disclaimer

* This only works with python 3.12.x release version, any other version are not guaranteed to match.
  * If anyone wants to change version, change the `python312` in line 25 of `build.zig` (and provide the corresponding version).
  * This package make use of immortal object, and python < 3.12 will not clean up these object on exit.
This is not memory leak (they are singleton and have static lifetime in python < 3.12).
* This is written in zig 0.14.0, any version greater than this will not guarantee to work.

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
