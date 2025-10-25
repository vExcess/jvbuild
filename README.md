# jvbuild
**J**SON5 **v**ersioned **build** system. jvbuild is a language-agnostic package manager, build system, and distribution tool.

NOTE: I would consider jvbuild a beta software. Do not expect it to be stable or complete.

## Currently Supported Languages
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
Before jvbuild can bootstrap itself, you must install its dependencies.
```bash
dart pub get
```
Next run jvbuild from source to build itself. jvbuild is selfhosted!
```bash
dart run src/jvbuild.dart build
```
Next use the compiled jvbuild binary to package itself for distribution
```bash
./jvbuild-out/jvbuild package
```
Congrats, you have used jvbuild to build and package itself!

## Platform Support
X = Not Supported  
P = Support Planned  
Y = Supported  
? = Maybe  
\- = Does Not Exist  

| Platform  | x64 | Arm64 | RISC-V |
| ------------- | ------------- | ------------- | ------------- |
| Windows 10/11      | P | X | - |
| macOS              | X | X | - |
| Debian-based Linux | Y | Y | P |
| Fedora-based Linux | P | P | P |
| Arch-based Linux   | P | P | P |
| Other Linux        | ? | ? | ? |