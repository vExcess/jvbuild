import 'dart:io';

import '../JVModule.dart';
import '../utils.dart';
import './LangPlugin.dart';

class DartPlugin extends LangPlugin {
    Future<void> build(JVModule module, CommandArgs args) async {
        // create pubspec
        if (args.isVerbose) {
            print("Creating pubspec.yaml");
        }
        final pubspecContents = translate(module, args);
        final file = File("pubspec.yaml");
        file.writeAsStringSync(pubspecContents);

        // install deps
        final installDepsRes = Process.runSync("dart", ["pub", "get"]);
        printOutAndErrIfExist(installDepsRes);

        // compile
        await Process.start("dart", ["compile", "exe", module.root, "-o", "./.jvbuild-out/${module.name}"], mode: ProcessStartMode.inheritStdio);
    }

    Future<void> run(JVModule module, CommandArgs args) async {
        // create pubspec
        if (args.isVerbose) {
            print("Creating pubspec.yaml");
        }
        final pubspecContents = translate(module, args);
        final file = File("pubspec.yaml");
        file.writeAsStringSync(pubspecContents);

        // install deps
        final installDepsRes = Process.runSync("dart", ["pub", "get"]);
        printOutAndErrIfExist(installDepsRes);

        // run
        await Process.start("dart", ["run", module.root], mode: ProcessStartMode.inheritStdio);
    }

    String translate(JVModule module, CommandArgs args) {
        var pubspec = """name: ${module.name}
version: ${module.version}

environment:
  sdk: ^3.5.3

dependencies:\n""";

        for (final depName in module.dependencies) {
            final dep = args.buildDef.modules[depName]!;
            pubspec += "  ${dep.name}: ${dep.version}\n";
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
