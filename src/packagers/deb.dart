import 'dart:io';
import '../JVModule.dart';
import '../CommandArgs.dart';
import './PackPlugin.dart';
import 'dart:typed_data';
import 'package:image/image.dart' as image;
import '../utils.dart';

class DebPlugin extends PackPlugin {
    Future<void> package(JVModule module, CommandArgs args) async {
        final packageName = module.name;
        final buildDef = args.buildDef;

        final arch = await getCPUArchitecture();

        final EXE_FILE_PATH = "./jvbuild-out/${packageName}";
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
        mkdir("./jvbuild-out");
        cp("./jvbuild-out/${packageName}", "${debPkgName}/usr/bin/${packageInfo["Package"]}");
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
        try {
            final buildRes = Process.runSync("dpkg-deb", ["--build", debPkgName]);
            printOutAndErrIfExist(buildRes);

            // move package to jvbuild-out and cleanup
            mv("./${debPkgName}.deb", "./jvbuild-out/${debPkgName}_${cpuArchToJvbuildArch[arch]!}.deb");
        } catch (e) {
            print("jvbuild: Something went wrong while running dpkg-deb\n${e}");
        }
        
        rm(debPkgName);
    }
}
