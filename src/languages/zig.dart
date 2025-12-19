import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;

import '../BuildDefinition.dart';
import '../JVModule.dart';
import './LangPlugin.dart';
import '../utils.dart';

class ZigPlugin extends LangPlugin {
    bool recursiveDependsOn(JVModule module, String targetDepName, BuildDefinition buildDef) {
        if (module.dependencies.contains(targetDepName)) {
            return true;
        }

        var dependsOn = false;
        for (final depName in module.dependencies) {
            final dep = buildDef.modules[depName];
            if (recursiveDependsOn(dep!, targetDepName, buildDef)) {
                dependsOn = true;
            }
        }
        return dependsOn;
    }

    List<String> getRecursiveDependencies(JVModule module, BuildDefinition buildDef, [Set<String>? aggregator]) {
        if (aggregator == null) {
            aggregator = new Set();
        }

        for (final depName in module.dependencies) {
            aggregator.add(depName);
            final dep = buildDef.modules[depName];
            getRecursiveDependencies(dep!, buildDef, aggregator);
        }

        return aggregator.toList();
    }

    Future<void> build_run(String command, JVModule module, CommandArgs args) async {
        List<String> callArgs = [(command == "run" ? "run" : "build-exe"), "-D_REENTRANT"];
        final jvmods = args.buildDef.modules.values.toList();
        List<String> buildEntryNames = [];
        if (args.buildDef.build[args.selector] != null) {
            buildEntryNames = args.buildDef.build[args.selector] as List<String>;
        }

        if (args.isVerbose) {
            print("buildMode: ${args.selector}");
            print("buildEntryNames: ${buildEntryNames.toString()}");
            print("modules: ${jvmods.toString()}");
        }

        // verify dependencies exist and include/link system libraries
        var encounteredErr = false;
        final allDepNames = getRecursiveDependencies(module, args.buildDef);
        for (final depName in allDepNames) {
            final dep = args.buildDef.modules[depName];
            
            if (dep == null) {
                print("jvbuild: unable to locate dependency: ${depName}");
                encounteredErr = true;
                continue;
            }

            if (dep.name != "libc" && dep.language == "system") {
                callArgs.add("-I/usr/include/${depName}");
                callArgs.add("-l${depName}");
            }
        }

        // return error value on failure
        if (encounteredErr) {
            print("try fetching dependencies using `jvbuild install` and making sure it's imported in your build.json5");
            return null;
        }

        final isLib = module.modType == ModuleType.LIB;
        final linkLibC = recursiveDependsOn(module, "libc", args.buildDef);
        final exeName = module.name;

        for (final mod in jvmods) {
            if (mod.language == "zig" && (mod.name == exeName || allDepNames.contains(mod.name))) {
                for (final depName in mod.dependencies) {
                    final dep = args.buildDef.modules[depName]!;
                    if (dep.language == "zig") {
                        callArgs.add("--dep");
                        callArgs.add("${depName}");
                    }
                }

                switch (args.optimizationLevel) {
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

                if (mod.name == exeName && !isLib) {
                    callArgs.add("-Mroot=${module.root}");
                } else {
                    callArgs.add("-M${mod.name}=${mod.root}");
                }
            }
        }

        if (isLib && callArgs[0] == "build-exe") {
            callArgs[0] = "build-lib";
            callArgs.add("-dynamic");
        }

        if (linkLibC) {
            callArgs.add("-lc");
        }
        
        final finalOutputPath = (args.outputPath.length > 0) ? args.outputPath : ("./jvbuild-out/${exeName}${isLib ? ".so" : ""}");

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

        if (args.isVerbose) {
            print("zig " + callArgs.join(" "));
        }

        await Process.start("zig", callArgs, mode: ProcessStartMode.inheritStdio);
    }

    Future<void> build(JVModule module, CommandArgs args) async {
        await build_run("build", module, args);
    }
    
    Future<void> run(JVModule module, CommandArgs args) async {
        await build_run("run", module, args);
    }

    String? translate(JVModule module, CommandArgs args) {
        final jvmods = args.buildDef.modules.values.toList();

        var out = """
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = """;

        // set optimization level
        switch (args.optimizationLevel) {
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
            if (mod.modType == ModuleType.LIB) {
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
        .optimize = optimize${recursiveDependsOn(mod, "libc", args.buildDef) ? ",\n        .link_libc = true" : ""}
    });\n\n""";
            }
        }

        // module/exe decl strings
        for (var i = 0; i < jvmods.length; i++) {
            final mod = jvmods[i];

            // add sub dependencies
            for (var j = 0; j < mod.dependencies.length; j++) {
                final depModName = mod.dependencies[j];
                if (mod.language == "system") {
                    out += "    exe_${mod.name}.linkSystemLibrary(\"${depModName}\");\n";
                } else if (mod.modType == ModuleType.LIB) {
                    out += "    mod_${mod.name}.addImport(\"${depModName}\", mod_${depModName});\n";
                } else {
                    out += "    exe_${mod.name}.root_module.addImport(\"${depModName}\", mod_${depModName});\n";
                }
            }
        }

        // compile exes
        out += "\n";
        for (var i = 0; i < jvmods.length; i++) {
            if (jvmods[i].modType != ModuleType.LIB) {
                out += "    b.installArtifact(exe_${jvmods[i].name});\n";
            }
        }

        out += "}";

        if (args.outputPath.isNotEmpty) {
            File(args.outputPath).writeAsStringSync(out);
        }

        return out;
    }
}
