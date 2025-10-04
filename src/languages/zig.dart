import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;

import '../JVModule.dart';
import './LangPlugin.dart';
import '../utils.dart';

class ZigPlugin extends LangPlugin {
    Future<void> build_run(String command, JVModule module, CommandArgs args) async {
        List<String> callArgs = [command == "run" ? "run" : "build-exe", "-D_REENTRANT"];
        final jvmods = args.buildDef.modules.values.toList();
        final buildEntryNames = args.buildDef.build[args.selector] as List<String>;

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

        if (args.isVerbose) {
            print("buildMode: ${args.selector}");
            print("buildEntryNames: ${buildEntryNames.toString()}");
            print("modules: ${jvmods.toString()}");
        }

        final buildEntryName = buildEntryNames[0];

        var linkLibC = false;
        var exeName = "";
        var entryIsLib = false;
        for (var i = 0; i < jvmods.length; i++) {
            final mod = jvmods[i];

            if (mod.modType == ModuleType.LIB) {
                for (var j = 0; j < mod.dependencies.length; j++) {
                    callArgs.add("--dep");
                    callArgs.add("${mod.dependencies[j]}");
                }
                callArgs.add("-M${mod.name}=${mod.root}");
            }
            
            if (mod.name == buildEntryName) {
                for (var j = 0; j < mod.dependencies.length; j++) {
                    final depName = mod.dependencies[j];
                    if (args.buildDef.modules[depName]!.language == "system"){
                        callArgs.add("-I/usr/include/${depName}");
                        callArgs.add("-l${depName}");
                    } else {
                        callArgs.add("--dep");
                        callArgs.add("${depName}");    
                    }
                }

                if (mod.dependencies.contains("libc")) {
                    linkLibC = true;
                }
                
                exeName = mod.name;
                entryIsLib = mod.modType == ModuleType.LIB;
                if (!entryIsLib) {
                    callArgs.add("-Mroot=${mod.root}");
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
        }

        if (entryIsLib && callArgs[0] == "build-exe") {
            callArgs[0] = "build-lib";
            callArgs.add("-dynamic");
        }

        if (linkLibC) {
            callArgs.add("-lc");
        }

        final finalOutputPath = (args.outputPath.length > 0) ? args.outputPath : "./jvbuild-out/${exeName}${entryIsLib ? ".so" : ""}";
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
        .optimize = optimize${mod.dependencies.contains("libc") ? ",\n        .link_libc = true" : ""}
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
