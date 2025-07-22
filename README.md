# jvbuild
**J**SON5 **v**ersioned **build** system. jvbuild is a language-agnostic package manager, build system, and distribution tool.

NOTE: I would consider jvbuild a beta software. Do not expect it to be stable or complete.

## Currently Support Languages
- Zig
- Dart

## Distribution Formats
- Debian Package (.deb)
- Fedora (.rpm) [Not Yet Implemented]
- Windows (.msi) [Not Yet Implemented]

## Example
See [https://github.com/librepaint/librepaint-3d](https://github.com/librepaint/librepaint-3d) for an example of a full project using jvbuild.

## Docs
See [docs.md](https://github.com/vExcess/jvbuild/blob/main/docs.md) for usage and documentation

## Building
jvbuild is self hosted! First use `dart run` to run jvbuild's `build` command on itself. This compiles jvbuild and outputs it to the `.jvbuild-out` directory.
```bash
dart run src/jvbuild.dart build
```
Next use the compiled jvbuild binary to package itself for distribution
```bash
./.jvbuild-out/jvbuild package
```