import 'dart:io';

import '../JVModule.dart';
import '../CommandArgs.dart';
import '../BuildDefinition.dart';


void mkdir(String dirName) {
    var dir = Directory(dirName);
    if (!dir.existsSync()) {
        dir.createSync(recursive: true);
    }
}

void mv(String src, String dst) {
    var file = File(src);
    file.renameSync(dst);
}

void rm(String src) {
    var file = File(src);
    if (file.existsSync()) {
        file.deleteSync();
        return;
    }

    var dir = Directory(src);
    if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
        return;
    }
}

void cp(String src, String dst) {
    var file = File(src);
    file.copySync(dst);
}

void fwrite(String dst, Object contents) {
    var file = File(dst);
    if (contents is String) {
        file.writeAsStringSync(contents);
    } else if (contents is List<int>) {
        file.writeAsBytesSync(contents);
    }
}


Future<String> getCPUArchitecture() async {
    String cpu;
    if (Platform.isWindows) {
        cpu = Platform.environment['PROCESSOR_ARCHITECTURE']!;
    } else {
        final info = await Process.run('uname', ['-m']);
        cpu = info.stdout.toString().replaceAll('\n', '');
    }
    switch (cpu.toLowerCase()) {
        case 'x86_64' || 'x64' || 'amd64':
            cpu = 'x86_64';
        case 'x86' || 'i386' || 'x32' || '386' || 'amd32':
            cpu = 'x86';
        case 'aarch32' || 'arm32':
            cpu = 'arm32';
        case 'aarch64' || 'arm64':
            cpu = 'arm64';
    }
    return cpu;
}

List<JVModule> allModuleDependencies(JVModule module, BuildDefinition buildDef, List<JVModule> accumulator) {
    for (final depName in module.dependencies) {
        final depModule = buildDef.modules[depName]!;
        accumulator.add(depModule);
        allModuleDependencies(depModule, buildDef, accumulator);
    }
    return accumulator;
}

Map<String, String> cpuArchToJvbuildArch = {
    "x86": "x86",
    "x86_64": "x64",
    "arm32": "arm32", // or armhf
    "arm64": "arm64",
};

class PackPlugin {
    Future<void> package(JVModule module, CommandArgs args) async {
        throw "PackPlugin.package must be implemented by child";
    }
}
