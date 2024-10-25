# Docs
## Global
`language` required :: String  
Name of programming language (currently only supports "zig")  

`modules` required :: Map of module definitions
Describes modules  

`build` optional :: Map<BuildModeName, Array<String>>  
List of modules to build for each build mode. "default" is the mode that runs if no command line args are passed in. If build is ommited then all modules are built by default  

`name` optional :: String  
Project name  

`version` optional :: String  
Project version  

`description` optional :: String  
Project description  

`author` optional :: String  
Project author  

`license` optional :: String  
License

## ModuleDefinition
`root` required :: String  
Path to module's entrypoint

`type` optional :: String  
Type of the module can be "exe" or "lib. If ommited defaults to "exe"

`dependencies` optional :: Array<String | [String]>  
The list of dependencies for the module. Modules wrapped in an array are system dependencies. There is a special system dependency "libc" that links the C standard library

## Module Imports
`$importAll` :: Array<ImportDefinition>
List of imports

## ImportDefinition
`local` optional :: String  
Path to local module directory

`remote` optional :: String  
Link to remote module repo