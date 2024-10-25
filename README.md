# jvbuild
A language agnostic build system in JSON5. Currently only has partial support for Zig. Feel free to create pull request expanding Zig support or adding support for other languages.

NOTE: jvbuild is in early beta. Do not expect it to be stable.

## Example
See test/test.json for example build.json5

## Docs
See docs.md for documentation

## Usage
```
jvbuild [buildMode] [options]
jvbuild [command] [buildMode] [flags]

commands:
  build      build the project without running it
  run        run the project
  translate  translate build.json5 to [build.zig, package.json, pubspec.yaml]

flags:
  -O, --Optimize  Set optimization level [debug, small, fast, safe]. Debug is the default
  -o, --output    Set output file
  -h, --help      Display help dialog
  -p, --path      Path to build.json5 (defaults to ./build.json5)
  -v, --verbose   Print module tree and compiler commands

examples:
  jvbuild build
  jvbuild translate --output=build.zig
  jvbuild run -p=myBuildFile.json5
  jvbuild run myBuildMode -O=Fast
```

## Building
`dart run deb-build.dart` will build the project and then generate a deb package for it. The compiled binary and deb package will be in the dist directory.