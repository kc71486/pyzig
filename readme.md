## pyzig

Binds python 3.12 with zig 0.15.1.

### Disclaimer

* The library is mainly for personal uses, it is not ready for use in production.
* The library might have some bugs, use with caution.
* This only works with python 3.12.x release version, python < 3.12 will cause some issues.
  * This package make use of immortal object (added in python 3.12), using python < 3.12 will cause some unwanted memory leaks.
* This is written in zig 0.15.1, any other major version is not guarantee to work.
  * Some functions that uses `std.io.Writer` will not work in 0.14.1.
    * Functions in question: `Builtin.print`.

### Features

* Wraps some basic python functions/Objects.
* Static link python library (release version).
  * The python library is then dynamically linked to system python library.

### Get Started

See `example`.

### Modifications

In order to change python version, change the `python312` in line 25 of `build.zig` (and provide the corresponding version).
