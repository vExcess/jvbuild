import 'dart:io';

import './utils.dart';

import './BuildDefinition.dart';
import './JVModule.dart';

import './packager.dart';

import './languages/LangPlugin.dart';
import 'languages/zig.dart';
import 'languages/dart.dart';

void makeSuggestions(Map<String, Object> options, String selector) {
    print("jvbuild: build mode `${selector}` is not defined");
    var maxSim = 0.0;
    var maxSimBuildMode = "";
    for (final buildModeName in options.keys) {
        final sim = LevDist(selector, buildModeName);
        if (sim > maxSim) {
            maxSim = sim;
            maxSimBuildMode = buildModeName;
        }
    }
    if (maxSimBuildMode.isNotEmpty) {
        print("did you mean `${maxSimBuildMode}`?");
    }
}

LangPlugin? getLangPlugin(JVModule module) {
    LangPlugin langPlug;
    try {
        langPlug = switch (module.language) {
            "zig" => new ZigPlugin(),
            "dart" => new DartPlugin(),
            "system" => new LangPlugin(),
            _ => throw "jvbuild: unsupported language"
        };
    } catch (e) {
        print(e);
        return null;
    }

    return langPlug;
}

const helpDialog = """jvbuild [buildMode] [options]
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
""";

void main(List<String> arguments) async {
    var filePath = "build.json5";
    var outputPath = "";
    var optimizationLevel = "default";
    var selector = "default";
    var hasOutputPath = false;
    var hasOptimizationLevel = false;
    var hasSelector = false;
    var isVerbose = false;
    var command = "";

    // parse arguments
    for (var i = 0; i < arguments.length; i++) {
        final arg = arguments[i];
        
        // --help      Display help dialog
        if (arg == "-h" || arg == "--help") {
            print(helpDialog);
            return;
        } 
        
        // --verbose   Print module tree and compiler commands
        else if (arg == "-v" || arg == "--verbose") {
            isVerbose = true;
        } 
        
        // --path      Path to build.json5 (defaults to ./build.json5)
        else if (arg.startsWith("-p") || arg.startsWith("--path")) {
            final argVal = arg.split("=");
            if (argVal.length == 2) {
                filePath = argVal[1];
            } else {
                print("jvbuild: invalid option argument");
                return;
            }
        } 
        
        // --output    Set output file
        else if (arg.startsWith("-o") || arg.startsWith("--output")) {
            if (hasOutputPath) {
                print("jvbuild: too many output path arguments");
                return;
            }
            final argVal = arg.split("=");
            if (argVal.length == 2) {
                outputPath = argVal[1];
            } else {
                print("jvbuild: invalid option argument");
                return;
            }
            hasOutputPath = true;
        } 
        
        // --Optimize  Set optimization level [debug, small, fast, safe]
        else if (arg.startsWith("-O") || arg.startsWith("--Optimize")) {
            if (hasOptimizationLevel) {
                print("jvbuild: too many optimization level arguments");
                return;
            }
            final argVal = arg.split("=");
            if (argVal.length == 2) {
                optimizationLevel = argVal[1].toLowerCase();
                const validList = ["debug", "small", "fast", "safe"];
                if (!validList.contains(optimizationLevel)) {
                    print("jvbuild: invalid optimization argument");
                    return;
                }
            } else {
                print("jvbuild: invalid option argument");
                return;
            }
            hasOptimizationLevel = true;
        } 
        
        // build      build modules without running them
        else if (arg == "build") {
            command = "build";
        }
        
        // run        run a script or module
        else if (arg == "run") {
            command = "run";
        } 
        
        // translate  translate build.json5 to [build.zig, package.json, pubspec.yaml]
        else if (arg == "translate") {
            command = "translate";
        } 

        // package  package a module for distribution
        else if (arg == "package") {
            command = "package";
        } 
        
        // catch extra arguments
        else {
            if (hasSelector) {
                print("jvbuild: too many build mode arguments");
                return;
            }
            selector = arg;
            hasSelector = true;
        }
    }

    // handle no commands given
    if (command == "") {
        print(helpDialog);
        return;
    }

    // parse file
    // if parseBuildFile errors, it prints its error, then returns null
    if (isVerbose) {
        print("Parsing ${filePath}");
    }
    final parsedFile = BuildDefinition.parseBuildFile(filePath, true);
    if (parsedFile != null) {
        // for (var i = 0; i < parsedFile.modules.length; i++) {
        //     final mod = parsedFile.modules[i];
        //     // if (!mod.isLib) {
        //         mod.propogateDependencies(parsedFile.modules);
        //     // }
        // }

        if (selector == "default" && parsedFile.defaultModule != null) {
            selector = parsedFile.defaultModule!;
        }


        final cmdArgs = CommandArgs(
            outputPath: outputPath,
            optimizationLevel: optimizationLevel,
            selector: selector,
            isVerbose: isVerbose,
            buildDef: parsedFile
        );

        var outDir = Directory("./.jvbuild-out");
        if (!outDir.existsSync()) {
            outDir.createSync();
        }

        switch (command) {
            case "package":
                final module = parsedFile.modules[selector];
                if (module != null) {
                    // for (final moduleName in packageModules) {
                    //     final module = parsedFile.modules[moduleName]!;
                    //     final langPlugin = getLangPlugin(module);
                    //     if (langPlugin == null) return;
                    //     langPlugin.build(module, cmdArgs);
                    // }
                    package(module, cmdArgs);
                } else {
                    makeSuggestions(parsedFile.modules, selector);
                    return;
                }

            case "run":
                final runScript = parsedFile.run[selector];
                final runModule = parsedFile.modules[selector];
                if (runScript != null) {
                    final bashProc = await Process.start("bash", []);
                    if (isVerbose) {
                        print(runScript);
                    }
                    bashProc.stdin.write("${runScript}\n");
                    bashProc.stdin.write("exit\n");
                    bashProc.stdout.pipe(stdout);
                    bashProc.stderr.pipe(stderr);
                } else if (runModule != null) {
                    final langPlugin = getLangPlugin(runModule);
                    if (langPlugin == null) return;
                    if (isVerbose) {
                        print("Running ${runModule.name}");
                    }
                    langPlugin.run(runModule, cmdArgs);
                } else {
                    makeSuggestions(parsedFile.run, selector);
                    makeSuggestions(parsedFile.modules, selector);
                    return;
                }

            case "build":
                final buildModules = parsedFile.build[selector];
                final buildModule = parsedFile.modules[selector];

                if (buildModules != null) {
                    for (final moduleName in buildModules) {
                        final module = parsedFile.modules[moduleName]!;
                        final langPlugin = getLangPlugin(module);
                        if (langPlugin == null) return;

                        if (isVerbose) {
                            print("Building ${module.name}");
                        }

                        langPlugin.build(module, cmdArgs);
                    }
                } else if (buildModule != null) {
                    if (isVerbose) {
                        print("Building ${buildModule.name}");
                    }

                    final langPlugin = getLangPlugin(buildModule);
                    if (langPlugin == null) return;
                    langPlugin.build(buildModule, cmdArgs);
                } else {
                    makeSuggestions(parsedFile.build, selector);
                    return;
                }
            

            // case "translate":
            //     print(gen_build_zig(parsedFile, buildMode, optimizationLevel));

        }
    }
}