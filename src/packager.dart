// https://wiki.debian.org/HowToPackageForDebian
// https://wiki.debian.org/Packaging/Intro

// https://specifications.freedesktop.org/desktop-entry-spec/latest/
// https://specifications.freedesktop.org/desktop-entry-spec/latest/recognized-keys.html

import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as image;

import './utils.dart';
import './JVModule.dart';
import './BuildDefinition.dart';
import './languages/LangPlugin.dart';

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

void package(JVModule module, CommandArgs args) async {
    final packageName = module.name;
    final buildDef = args.buildDef;

    final arch = await getCPUArchitecture();

    final EXE_FILE_PATH = "./.jvbuild-out/${packageName}";
    final fileSize = (await File(EXE_FILE_PATH).length()) / 1024;

    Map<String, String> cpuArchToDebArch = {
        "x86": "i386",
        "x86_64": "amd64",
        "arm32": "armel", // or armhf
        "arm64": "arm64",
    };

    if (!cpuArchToDebArch.containsKey(arch)) {
        print("jvbuild: unsupported CPU architecture: ${arch}");
        return;
    }

    final allDeps = allModuleDependencies(module, buildDef, []);
    final sysDeps = allDeps.where((mod) => mod.language == "system");
    final debPackageNames = sysDeps.map<String>((mod) {
        final installers = mod.install;
        for (final oses in installers.keys) {
            if (oses.contains("debian")) {
                return installers[oses]!.split(" ").last;
            }
        }
        throw "unable to find system package name";
    });

    Map<String, String> desktopInfo = {
        "Version": module.version,
        "Type": "Application",
        "Name": buildDef.name,
        "Comment": buildDef.description,
        "TryExec": "/usr/bin/${module.name}",
        "Exec": "/usr/bin/${module.name} %U",
        "Icon": "/usr/share/icons/hicolor/${256}x${256}/apps/${packageName}.png",
        "Categories": buildDef.categories.join(";"),
    };
    if (buildDef.genericName != null) {
        desktopInfo["GenericName"] = buildDef.genericName!;
    }
    if (buildDef.keywords.isNotEmpty) {
        desktopInfo["Keywords"] = buildDef.keywords.join(";");
    }
    if (buildDef.mimeType.isNotEmpty) {
        desktopInfo["MimeType"] = buildDef.mimeType.join(";");
    }

    var desktopContents = "[Desktop Entry]\n";
    for (final key in desktopInfo.keys) {
        desktopContents += "${key}=${desktopInfo[key]}\n";
    }

    if (buildDef.icon != null && args.isVerbose) {
        print(desktopContents);
    }

    final postinst = """#!/bin/sh
set -e

# Update the desktop file database
update-desktop-database /usr/share/applications >/dev/null || true

exit 0""";
    final prerm = postinst;

    Map<String, String> packageInfo = {
        "Package": packageName,
        "Version": module.version,
        "Installed-Size": fileSize.round().toString(),
        "Section": "base",
        "Priority": "optional",
        "Architecture": cpuArchToDebArch[arch]!,
        "Depends": debPackageNames.join(", "),
        "Maintainer": buildDef.author,
        "Description": "${packageName}\n${buildDef.description}".trim().split("\n").map((s) => " ${s.trim()}").join("\n")
    };

    var controlContents = "";
    for (final key in packageInfo.keys) {
        controlContents += "${key}: ${packageInfo[key]}\n";
    }

    if (args.isVerbose) {
        print(controlContents);
    }

    List<int> iconSizes = [
        16, 24, 32, 48, 64, 128, 256, 512
    ];

    late File iconFile;
    if (buildDef.icon != null) {
        iconFile = File(buildDef.icon!);
        if (!iconFile.existsSync()) {
            print("jvbuild: icon file doesn't exist");
            return;
        }
    }
    
    // setup deb filetree
    final debPkgName = "${packageName}_${packageInfo["Version"]}";
    rm(debPkgName);
    mkdir("${debPkgName}/DEBIAN");
    mkdir("${debPkgName}/usr/bin");
    if (buildDef.icon != null) {
        mkdir("${debPkgName}/usr/share/applications/");
        for (final size in iconSizes) {
            mkdir("${debPkgName}/usr/share/icons/hicolor/${size}x${size}/apps");
        }
    }

    // copy over compiled binaries, metadata, and install scripts
    mkdir("./.jvbuild-out");
    mv(EXE_FILE_PATH, "./.jvbuild-out/${packageName}");
    cp("./.jvbuild-out/${packageName}", "${debPkgName}/usr/bin/${packageInfo["Package"]}");
    fwrite("${debPkgName}/DEBIAN/control", controlContents);
    if (buildDef.icon != null) {
        fwrite("${debPkgName}/usr/share/applications/${packageName}.desktop", desktopContents);
        fwrite("${debPkgName}/DEBIAN/postinst", postinst);
        fwrite("${debPkgName}/DEBIAN/prerm", prerm);
        final res1 = Process.runSync("chmod", ["0755", "${debPkgName}/DEBIAN/postinst"]);
        printOutAndErrIfExist(res1);
        final res2 = Process.runSync("chmod", ["0755", "${debPkgName}/DEBIAN/prerm"]);
        printOutAndErrIfExist(res2);
        for (final size in iconSizes) {
            final iconImg = image.decodePng(iconFile.readAsBytesSync());
            if (iconImg == null) {
                print("jvbuild: failed to decode icon png file");
                return;
            }
            final resizedImg = image.copyResize(iconImg,
                width: size,
                height: size,
            );
            Uint8List recoded = image.encodePng(resizedImg);

            fwrite("${debPkgName}/usr/share/icons/hicolor/${size}x${size}/apps/${packageName}.png", recoded.toList());
        }
    }

    // build package
    final buildRes = Process.runSync("dpkg-deb", ["--build", debPkgName]);
    printOutAndErrIfExist(buildRes);

    // move package to .jvbuild-out and cleanup
    mv("./${debPkgName}.deb", "./.jvbuild-out/${debPkgName}_${packageInfo["Architecture"]}.deb");
    rm(debPkgName);

    print("Build Complete!");
}
