import 'dart:async';
import 'dart:io';
import 'dart:math' as Math;
import 'package:json5/json5.dart';
import 'dart:convert';
import 'package:path/path.dart' as path;

dynamic findOne(List<dynamic> arr, bool Function(dynamic) filter) {
    for (var i = 0; i < arr.length; i++) {
        if (filter(arr[i])) {
            return arr[i];
        }
    }
    return null;
}

// ported from https://stackoverflow.com/questions/10473745/compare-strings-javascript-return-of-likely
int editDistance(String s1, String s2) {
    s1 = s1.toLowerCase();
    s2 = s2.toLowerCase();

    var costs = List.filled(s2.length + 1, 0);
    for (var i = 0; i <= s1.length; i++) {
        var lastValue = i;
        for (var j = 0; j <= s2.length; j++) {
            if (i == 0) {
                costs[j] = j;
            } else if (j > 0) {
                var newValue = costs[j - 1];
                if (s1[i - 1] != s2[j - 1]) {
                    newValue = Math.min(Math.min(newValue, lastValue), costs[j]) + 1;
                }
                costs[j - 1] = lastValue;
                lastValue = newValue;
            }
        }
        if (i > 0) {
            costs[s2.length] = lastValue;
        }
    }
    return costs[s2.length];
}
double LevDist(String s1, String s2) {
    var longer = s1;
    var shorter = s2;
    if (s1.length < s2.length) {
        longer = s2;
        shorter = s1;
    }
    var longerLength = longer.length;
    if (longerLength == 0) {
        return 1.0;
    }
    return (longerLength - editDistance(longer, shorter)) / longerLength;
}

List<String> getSysLibs(dynamic modObj, dynamic modules) {
    final deps = modObj["dependencies"];
    List<String> sysDeps = [];
    if (deps is List) {
        for (var i = 0; i < deps.length; i++) {
            if (deps[i] is List) {
                sysDeps.add(deps[i][0]);
            } else {
                print("getSysLibs: ${deps[i]}");
                final depName = deps[i];
                if (modules[depName]) {
                    final subSysLibs = getSysLibs(modules[depName], modules);
                    for (var i = 0; i < subSysLibs.length; i++) {
                        sysDeps.add(subSysLibs[i]);
                    }
                }
            }
        }
    }
    return sysDeps;
}

class JVModule {
    String name = "";
    bool isLib = false;
    String root = "";
    List<String> dependencies = [];
    List<String> sysLibraries = [];
    bool linkLibC = false;

    JVModule({
        required String name,
        required bool isLib,
        required String root,
        required List<String> dependencies,
        required List<String> sysLibraries,
        required bool linkLibC,
    }) {
        this.name = name;
        this.isLib = isLib;
        this.root = root;
        this.dependencies = dependencies;
        this.sysLibraries = sysLibraries;
        this.linkLibC = linkLibC;
    }

    void propogateDependencies(List<JVModule> modules) {
        final deps = this.dependencies;
        List<String> sysDeps = [];
        for (var i = 0; i < deps.length; i++) {
            final depMod = findOne(modules, (mod) => mod.name == deps[i]);
            if (depMod != null) {
                depMod.propogateDependencies(modules);

                // move up system dependencies
                for (var j = 0; j < depMod.sysLibraries.length; j++) {
                    final sysLib = depMod.sysLibraries[j];
                    if (!this.sysLibraries.contains(sysLib)) {
                        this.sysLibraries.add(sysLib);
                    }
                }

                // move up libc
                if (depMod.linkLibC) {
                    this.linkLibC = true;
                }
            } else {
                print("jvbuild: failed to locate module ${deps[i]}");
            }
        }

        // link libc
        for (var i = 0; i < this.sysLibraries.length; i++) {
            if (this.sysLibraries[i] == "libc") {
                this.linkLibC = true;
                this.sysLibraries.removeAt(i);
                break;
            }
        }
    }

    String toString() {
        return """{
    name: ${this.name},
    isLib: ${this.isLib},
    root: ${this.root},
    dependencies: ${this.dependencies},
    sysLibraries: ${this.sysLibraries},
    linkLibC: ${this.linkLibC},
}""";
    }
}

List<JVModule> parseMods(Map<String, dynamic> jsonModules, String dirUri) {
    List<JVModule> out = [];

    for (final prop in jsonModules.keys) {
        final itemName = prop is String ? prop : null;
        if (itemName != null) {
            if (itemName[0] != "\$") {
                final modJSON = jsonModules[itemName];

                List<String> sysLibraries = [];
                List<String> dependencies = [];
                final dependenciesJSON = modJSON["dependencies"];
                if (dependenciesJSON != null) {
                    for (var i = 0; i < dependenciesJSON.length; i++) {
                        final item = dependenciesJSON[i];
                        if (item is List) {
                            sysLibraries.add(item[0]);
                        } else {
                            dependencies.add(item);
                        }
                    }
                }

                var rootStr = "";
                if (modJSON["root"] != null) {
                    rootStr = Uri.file(dirUri).resolve(modJSON["root"]).toString().substring("file://".length);
                }

                out.add(JVModule(
                    name: itemName,
                    isLib: modJSON["type"] == "lib",
                    root: rootStr,
                    dependencies: dependencies,
                    sysLibraries: sysLibraries,
                    linkLibC: false
                ));
            }
        } else {
            print("jvbuild: something went wrong");
        }
    }

    return out;
}

typedef FileModule = ({
    List<JVModule> mods,
    Map<String, List<String>> buildModes,
    String lang,
});

FileModule? parseBuildFile(String filePath, bool isEntrypoint) {
    final file = File(filePath);
    
    if (file.existsSync()) {
        final contents = file.readAsStringSync();
        var parsed;
        try {
            parsed = JSON5.parse(contents);
        } catch (e) {
            print("jvbuild: invalid json5 file\n\t$e");
        }

        final buildSpec = parsed is Map<String, dynamic> ? parsed : null;
        if (buildSpec == null) {
            print("jvbuild: something went wrong");
            return null;
        }

        var lang = buildSpec["language"];
        if (lang == null) {
            print("jvbuild: target language is unspecified");
            return null;
        }
        lang = lang.toLowerCase();

        var buildModesDynamic = buildSpec["build"];
        Map<String, List<String>> buildModes = {};
        if (buildModesDynamic == null) {
            buildModes["default"] = ["main"];
        } else {
            for (final prop in buildModesDynamic.keys) {
                List<String> temp = [];
                final buildModesList = buildModesDynamic[prop] as List<dynamic>;
                for (var i = 0; i < buildModesList.length; i++) {
                    temp.add(buildModesList[i] as String);
                }
                buildModes[prop] = temp;
            }
        }

        if (buildSpec["modules"] == null) {
            print("jvbuild: build definition not found");
            return null;
        }

        final jsonModules = buildSpec["modules"];
        var outMods = parseMods(jsonModules, file.absolute.path);
        for (var itemName in jsonModules.keys) {
            if (itemName == "\$importAll") {
                // loop through all imports
                final subJSONModules = jsonModules[itemName];
                if (subJSONModules is List) {
                    for (var i = 0; i < subJSONModules.length; i++) {
                        final temp = file.absolute.path;
                        var backWalk = temp.length - 1;
                        while (backWalk >= 0 && temp[backWalk] != '/') {
                            backWalk--;
                        }
                        final localPath = temp.substring(0, backWalk + 1) + subJSONModules[i]["local"];
                        if (localPath != null) {
                            // import sub modules
                            final res = parseBuildFile(localPath + "/build.json5", false);
                            if (res != null) {
                                for (var i = 0; i < res.mods.length; i++) {
                                    final alreadyHas = findOne(outMods, (mod) => mod.name == res.mods[i].name) != null;
                                    if (!alreadyHas) {
                                        outMods.add(res.mods[i]);
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                for (var i = 0; i < itemName.length; i++) {
                    final ch = itemName.codeUnitAt(i);
                    if (!(
                        // is uppercase
                        (ch >= 65 && ch <= 90) ||
                        // is lowercase
                        (ch >= 97 && ch <= 122) ||
                        // is number
                        (ch >= 48 && ch <= 57) ||
                        // is underscore or dash
                        ch == 95 || ch == 45)
                    ) {
                        print("jvbuild: invalid name: ${itemName}");
                    }
                }
            }
        }

        FileModule out = (
            mods: outMods,
            buildModes: buildModes,
            lang: lang
        );

        return out;
    } else {
        print("jvbuild: file not found [${filePath}](${file.absolute.path})");
    }
    return null;
}

void zig_build_run(String command, FileModule fileModule, String buildMode, String optimizationLevel, bool verbose, String outputPath) async {
    List<String> callArgs = [command == "run" ? "run" : "build-exe", "-D_REENTRANT"];
    final jvmods = fileModule.mods;
    final buildEntryNames = fileModule.buildModes[buildMode] as List<String>;

    // verify that modules exist
    for (var i = 0; i < buildEntryNames.length; i++) {
        final modName = buildEntryNames[i];
        final mod = findOne(jvmods, (mod) => mod.name == modName);
        if (mod == null) {
            print("jvbuild: module `${modName}` does not exist");
            var maxSim = 0.0;
            var maxSimBuildMode = "";
            for (var j = 0; j < jvmods.length; j++) {
                final jvmodName = jvmods[j].name;
                final sim = LevDist(modName, jvmodName);
                if (sim > maxSim) {
                    maxSim = sim;
                    maxSimBuildMode = jvmodName;
                }
            }
            print("did you mean `${maxSimBuildMode}`?");
            return;
        }
    }

    if (verbose) {
        print("buildMode: " + buildMode);
        print("buildEntryNames: " + buildEntryNames.toString());
        print("modules: " + jvmods.toString());
    }

    final buildEntryName = buildEntryNames[0];

    var linkLibC = false;
    var exeName = "";
    var entryIsLib = false;
    for (var i = 0; i < jvmods.length; i++) {
        final mod = jvmods[i];

        if (mod.isLib) {
            for (var j = 0; j < mod.dependencies.length; j++) {
                callArgs.add("--dep");
                callArgs.add("${mod.dependencies[j]}");
            }
            callArgs.add("-M${mod.name}=${mod.root}");
        }
        
        if (mod.name == buildEntryName) {
            for (var j = 0; j < mod.dependencies.length; j++) {
                callArgs.add("--dep");
                callArgs.add("${mod.dependencies[j]}");
            }
            for (var j = 0; j < mod.sysLibraries.length; j++) {
                final sysLibName = mod.sysLibraries[j];
                callArgs.add("-I/usr/include/${sysLibName}");
                callArgs.add("-l${sysLibName}");
            }

            if (mod.linkLibC) {
                linkLibC = true;
            }
            
            exeName = mod.name;
            entryIsLib = mod.isLib;
            if (!entryIsLib) {
                callArgs.add("-Mroot=${mod.root}");
            }
        }

        switch (optimizationLevel) {
            case "default":
                callArgs.add("-ODebug");
            case "debug":
                callArgs.add("-ODebug");
            case "small":
                callArgs.add("-OReleaseSmall");
            case "fast":
                callArgs.add("-OReleaseFast");
            case "safe":
                callArgs.add("-OReleaseSafe");
        }
    }

    if (entryIsLib && callArgs[0] == "build-exe") {
        callArgs[0] = "build-lib";
        callArgs.add("-dynamic");
    }

    if (linkLibC) {
        callArgs.add("-lc");
    }

    final finalOutputPath = (outputPath.length > 0) ? outputPath : "./zig-out/bin/${exeName}${entryIsLib ? ".so" : ""}";
    if (command == "build") {
        callArgs.add("--cache-dir");
        callArgs.add("./.zig-cache");
        callArgs.add("--global-cache-dir");
        callArgs.add("/home/vexcess/.cache/zig");
        callArgs.add("-femit-bin=${finalOutputPath}");
    }

    final file = File("./zig-out/bin/${exeName}");
    
    if (!file.existsSync()) {
        await file.create(recursive: true);
    }

    if (verbose) {
        print("zig " + callArgs.join(" "));
    }

    await Process.start("zig", callArgs, mode: ProcessStartMode.inheritStdio);
}

String gen_build_zig(FileModule fileModule, String buildMode, String optimizationLevel) {
    final jvmods = fileModule.mods;

    var out = """
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = """;

    // set optimization level
    switch (optimizationLevel) {
        case "default":
            out += "b.standardOptimizeOption(.{});";
        case "debug":
            out += ".Debug;";
        case "small":
            out += ".ReleaseSmall;";
        case "fast":
            out += ".ReleaseFast;";
        case "safe":
            out += ".ReleaseSafe;";
    }
    out += "\n\n";

    // declare modules
    final jsonEncoder = JsonEncoder();
    for (var i = 0; i < jvmods.length; i++) {
        final mod = jvmods[i];
        final rootStr = jsonEncoder.convert(path.relative(mod.root));

        // create modStr
        if (mod.isLib) {
            out += """
    const mod_${mod.name} = b.createModule(.{
        .root_source_file = b.path(${rootStr}),
        .target = target,
        .optimize = optimize
    });\n\n""";
        } else {
            out += """
    const exe_${mod.name} = b.addExecutable(.{
        .name = "${mod.name}",
        .root_source_file = b.path(${rootStr}),
        .target = target,
        .optimize = optimize${mod.linkLibC ? ",\n        .link_libc = true" : ""}
    });\n\n""";
        }
    }

    // module/exe decl strings
    for (var i = 0; i < jvmods.length; i++) {
        final mod = jvmods[i];

        // add sub dependencies
        for (var j = 0; j < mod.dependencies.length; j++) {
            final depModName = mod.dependencies[j];
            if (mod.isLib) {
                out += "    mod_${mod.name}.addImport(\"${depModName}\", mod_${depModName});\n";
            } else {
                out += "    exe_${mod.name}.root_module.addImport(\"${depModName}\", mod_${depModName});\n";
            }
        }

        // add sys libs
        if (!mod.isLib) {
            for (var j = 0; j < mod.sysLibraries.length; j++) {
                final sysLibName = mod.sysLibraries[j];
                if (sysLibName != "libc") {
                    out += "    exe_${mod.name}.linkSystemLibrary(\"${sysLibName}\");\n";
                }
            }
        }
    }

    // compile exes
    out += "\n";
    for (var i = 0; i < jvmods.length; i++) {
        if (!jvmods[i].isLib) {
            out += "    b.installArtifact(exe_${jvmods[i].name});\n";
        }
    }

    out += "}";

    return out;
}

const helpDialog = """jvbuild [buildMode] [options]
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
""";

void main(List<String> arguments) {
    var filePath = "build.json5";
    var outputPath = "";
    var optimizationLevel = "default";
    var buildMode = "default";
    var hasOutputPath = false;
    var hasOptimizationLevel = false;
    var hasBuildMode = false;
    var isVerbose = false;
    var command = "build";
    for (var i = 0; i < arguments.length; i++) {
        final arg = arguments[i];
        if (arg == "-h" || arg == "--help") {
            print(helpDialog);
            return;
        } else if (arg == "-v" || arg == "--verbose") {
            isVerbose = true;
        } else if (arg.startsWith("-p") || arg.startsWith("--path")) {
            final argVal = arg.split("=");
            if (argVal.length == 2) {
                filePath = argVal[1];
            } else {
                print("jvbuild: invalid option argument");
                return;
            }
        } else if (arg.startsWith("-o") || arg.startsWith("--output")) {
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
            hasOptimizationLevel = true;
        } else if (arg.startsWith("-O") || arg.startsWith("--Optimize")) {
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
        } else if (arg == "build") {
            command = "build";
        } else if (arg == "run") {
            command = "run";
        } else if (arg == "translate") {
            command = "translate";
        } else {
            if (hasBuildMode) {
                print("jvbuild: too many build mode arguments");
                return;
            }
            buildMode = arg;
            hasBuildMode = true;
        }
    }

    final parsedFile = parseBuildFile(filePath, true);
    if (parsedFile != null) {
        for (var i = 0; i < parsedFile.mods.length; i++) {
            final mod = parsedFile.mods[i];
            // if (!mod.isLib) {
                mod.propogateDependencies(parsedFile.mods);
            // }
        }

        switch (parsedFile.lang) {
            case "zig":
                switch (command) {
                    case "run" || "build":
                        final buildModes = parsedFile.buildModes;
                        if (buildModes[buildMode] == null) {
                            print("jvbuild: build mode `${buildMode}` is not defined");
                            var maxSim = 0.0;
                            var maxSimBuildMode = "";
                            for (final buildModeName in buildModes.keys) {
                                final sim = LevDist(buildMode, buildModeName);
                                if (sim > maxSim) {
                                    maxSim = sim;
                                    maxSimBuildMode = buildModeName;
                                }
                            }
                            print("did you mean `${maxSimBuildMode}`?");
                            return;
                        }
                        zig_build_run(command, parsedFile, buildMode, optimizationLevel, isVerbose, outputPath);
                    case "translate":
                        print(gen_build_zig(parsedFile, buildMode, optimizationLevel));
                }
            default:
                print("jvbuild: unknown target language");
                return;
        }
    }
}