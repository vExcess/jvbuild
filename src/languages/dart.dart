import 'dart:io';

import '../jvbuild.dart';
import '../JVModule.dart';
import '../utils.dart';
import './LangPlugin.dart';

class DartPlugin extends LangPlugin {
    // return true on success
    bool _build_run_setup(JVModule module, CommandArgs args) {
        // create pubspec
        if (args.isVerbose) {
            print("Creating pubspec.yaml");
        }
        final pubspecContents = translate(module, args);
        if (pubspecContents == null) {
            return false;
        }
        final file = File("pubspec.yaml");
        file.writeAsStringSync(pubspecContents);

        // check find deps from locally
        var installDepsRes = Process.runSync("dart", ["pub", "get", "--offline"]);
        if (args.isVerbose) {
            printOutAndErrIfExist(installDepsRes);
        }
        if (installDepsRes.stderr.toString().contains("Try again without --offline")) {
            installDepsRes = Process.runSync("dart", ["pub", "get"]);
            printOutAndErrIfExist(installDepsRes);
        }
        return true;
    }

    Future<void> build(JVModule module, CommandArgs args) async {
        if (!_build_run_setup(module, args)) {
            return;
        }

        // compile
        await Process.start("dart", ["compile", "exe", module.root, "-o", "./jvbuild-out/${module.name}"], mode: ProcessStartMode.inheritStdio);
    }

    Future<void> run(JVModule module, CommandArgs args) async {
        if (!_build_run_setup(module, args)) {
            return;
        }

        // run
        await Process.start("dart", ["run", module.root], mode: ProcessStartMode.inheritStdio);
    }

    String? translate(JVModule module, CommandArgs args) {
        var pubspec = """name: ${module.name}
version: ${module.version}

environment:
  sdk: ^3.6.0

dependencies:\n""";

        var encounteredErr = false;
        for (final depName in module.dependencies) {
            final dep = args.buildDef.modules[depName];
            if (dep == null) {
                print("jvbuild: unable to locate dependency: ${depName}");
                encounteredErr = true;
                continue;
            }
            if (dep.language == "dart") {
                if (dep.root.isNotEmpty) {
                    var outputFlag = "--output=${dep.root}";
                    if (outputFlag[outputFlag.length - 1] != "/") {
                        outputFlag += "/";
                    }
                    outputFlag += "pubspec.yaml";

                    if (args.isVerbose) {
                        print(["jvbuild", "translate", dep.name, outputFlag, "--path=${dep.buildFilePath}"]);
                    }

                    jvbuild(["translate", dep.name, outputFlag, "--path=${dep.buildFilePath}"]);
                    pubspec += "  ${dep.name}:\n    path: ${dep.root}\n";
                } else {
                    pubspec += "  ${dep.name}: ${dep.version}\n";
                }
            }
        }

        if (encounteredErr) {
            print("try fetching dependencies using `jvbuild install` and making sure it's imported in your build.json5");
            return null;
        }

        pubspec += """\ndev_dependencies:
  lints: ^4.0.0
  test: ^1.24.0
""";

        for (final depName in module.devDependencies) {
            final dep = args.buildDef.modules[depName]!;
            pubspec += "  ${dep.name}: ${dep.version}";
        }

        return pubspec;
    }
}
