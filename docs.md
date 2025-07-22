# Docs
## Usage
```
jvbuild [buildMode] [options]
jvbuild [command] [buildMode] [flags]

commands:
  build      build modules without running them
  run        run a script or module
  translate  translate build.json5 to [build.zig, package.json, pubspec.yaml]
  package    package a module for distribution

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

## Overview
Each build.json5 file describes a project. Each project contains a few top level fields such as name, description, author, repository, and license. Many of which are optional. The project then contains modules which are the executables and libraries that make up the project. jvbuild commands can be defined so as to build the modules, run scripts, run modules, translate the jvbuild to a language's native package manager format, or package modules for distribution.

### Note on `build` command
build first searches for a list of modules in the build property of the project. If none is found, it will try building a module directly.

### Note on `run` command
run searches first for a run script. If none exists, it will try running a module directly.

## Project Fields
`name` optional :: String  
Project name  

`description` optional :: String  
Project description  

`author` optional :: String  
Project author  

`repository` optional :: String  
Repository link  

`license` optional :: String  
License

`modules` required :: Map of module definitions
Describes modules  

`build` optional :: Map<BuildModeName, Array<String>>  
List of modules to build for each build mode. "default" is the mode that runs if no command line args are passed in.

`run` optional :: Map<RunModeName, String>  
String containing a command to run.

## ModuleDefinition
`name` optional* :: String  
If the module is NOT being declared in the global `modules` field, then a name is required.

`type` optional :: String  
Module language followed by a colon and either "exe" (for executables) or "lib" (for libraries). ex: `dart:exe` or `zig:lib`. If excluded defaults to exe and the language of the file in the `root` field.

`version` optional :: String  
Project version in `0.0.0` format. Use `^0.0.0` to define a minimum version requirement.

`root` optional* :: String  
Path to module's entrypoint. This field is not required only if the module is a language or system package. ex: `src/main.zig`

`install` optional* :: Map<OSNames, String>  
Install scripts required if the module is a system package. Each OS will have its own install script. OSes sharing an install script can be joined with an underscore. ex:
```js
install: {
    debian_ubuntu: "sudo apt-get install blah",
    arch: "pacman blah blah",
    windows: "winget blah blah",
}
```

`dependencies` optional :: Array<String | ModuleDefinition>  
The list of dependencies for the module. Dependencies can be a string containing the name of a module, or a module definition itself. There is a special system dependency "libc" that links the C standard library

`dev_dependencies` optional :: Array<String | ModuleDefinition>  
Same as dependencies, but these ones are only needed for development and not distribution.

## Module Imports
`$importAll` :: Array<ImportDefinition>
List of imports

## ImportDefinition
`local` optional :: String  
Path to local module directory. This overrides the remote repository if it exists. Otherwise the remote repository is used.

`remote` optional :: String  
Link to remote module repo
