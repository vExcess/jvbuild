import 'dart:io';
import '../JVModule.dart';
import '../CommandArgs.dart';
import './PackPlugin.dart';
import 'dart:typed_data';
import 'package:image/image.dart' as image;
import '../utils.dart';

String getRpmDate() {
    final date = DateTime.now();
    // Dart's weekday starts at 1 (Monday) and ends at 7 (Sunday)
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    String weekday = weekdays[date.weekday - 1];
    String month = months[date.month - 1];
    int day = date.day;
    int year = date.year;

    return '${weekday} ${month} ${day} ${year}';
}

class RpmPlugin extends PackPlugin {
    Future<void> package(JVModule module, CommandArgs args) async {
        final packageName = module.name;
        final buildDef = args.buildDef;

        final arch = await getCPUArchitecture();

        final EXE_FILE_PATH = "./jvbuild-out/${packageName}";
        final fileSize = (await File(EXE_FILE_PATH).length()) / 1024;
        
        Map<String, String> cpuArchToRpmArch = {
            // "x86": "i386",
            "x86_64": "x86_64",
            // "arm32": "armel", // or armhf
            "arm64": "aarch64",
        };

        if (!cpuArchToRpmArch.containsKey(arch)) {
            print("jvbuild: unsupported CPU architecture: ${arch}");
            return;
        }

        final rpmArch = cpuArchToRpmArch[arch]!;

        final allDeps = allModuleDependencies(module, buildDef, []);
        final sysDeps = allDeps.where((mod) => mod.language == "system");
        final rpmPackageNames = sysDeps.map<String>((mod) {
            final installers = mod.install;
            for (final oses in installers.keys) {
                if (oses.contains("fedora")) {
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

        var specContents = """
# prevent rpm from complaining about the binary not being a C binary
%global debug_package %{nil}
%global __debug_install_post %{nil}
%global _build_id_links none

# prevent rpm from trying to replace C debug symbols in Dart binary resulting in corrupted binary
%global __strip /bin/true
%global __os_install_post %{nil}

Name:           ${module.name}
Version:        ${module.version}
Release:        1
Summary:        ${buildDef.description}
BuildArch:      ${rpmArch}

License:        ${buildDef.license.isNotEmpty ? buildDef.license : "Unknown"}
Source0:        %{name}-%{version}.tar.gz

${rpmPackageNames.isNotEmpty ? "Requires: ${rpmPackageNames.join(" ")}" : ""}

%description
${buildDef.description}

%prep
%setup -q

%install
rm -rf \$RPM_BUILD_ROOT
mkdir -p \$RPM_BUILD_ROOT/%{_bindir}
cp %{name} \$RPM_BUILD_ROOT/%{_bindir}

%clean
rm -rf \$RPM_BUILD_ROOT

%files
%{_bindir}/%{name}

%changelog
* ${getRpmDate()} ${buildDef.author}
- Version ${module.version} packaged
""";

        if (args.isVerbose) {
            print(specContents);
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
        
        // setup rpm filetree
        rm("rpmbuild");
        mkdir("rpmbuild/BUILD");
        mkdir("rpmbuild/RPMS");
        mkdir("rpmbuild/SOURCES");
        mkdir("rpmbuild/SPECS");
        mkdir("rpmbuild/SRPMS");
        final rpmPkgName = "${packageName}-${module.version}";
        // if (buildDef.icon != null) {
        //     mkdir("${debPkgName}/usr/share/applications/");
        //     for (final size in iconSizes) {
        //         mkdir("${debPkgName}/usr/share/icons/hicolor/${size}x${size}/apps");
        //     }
        // }

        // copy over compiled binaries, metadata, and install scripts
        mkdir("rpmbuild/SOURCES/${rpmPkgName}");
        cp("./jvbuild-out/${packageName}", "rpmbuild/SOURCES/${rpmPkgName}/${packageName}");
        final tarRes = Process.runSync("tar", ["-czf", "rpmbuild/SOURCES/${rpmPkgName}.tar.gz", "-C", "rpmbuild/SOURCES", rpmPkgName]);
        printOutAndErrIfExist(tarRes);
        rm("rpmbuild/SOURCES/${rpmPkgName}/${packageName}");
        fwrite("rpmbuild/SPECS/${packageName}.spec", specContents);
        // if (buildDef.icon != null) {
        //     fwrite("${rpmPkgName}/usr/share/applications/${packageName}.desktop", desktopContents);
        //     fwrite("${rpmPkgName}/DEBIAN/postinst", postinst);
        //     fwrite("${rpmPkgName}/DEBIAN/prerm", prerm);
        //     final res1 = Process.runSync("chmod", ["0755", "${rpmPkgName}/DEBIAN/postinst"]);
        //     printOutAndErrIfExist(res1);
        //     final res2 = Process.runSync("chmod", ["0755", "${rpmPkgName}/DEBIAN/prerm"]);
        //     printOutAndErrIfExist(res2);
        //     for (final size in iconSizes) {
        //         final iconImg = image.decodePng(iconFile.readAsBytesSync());
        //         if (iconImg == null) {
        //             print("jvbuild: failed to decode icon png file");
        //             return;
        //         }
        //         final resizedImg = image.copyResize(iconImg,
        //             width: size,
        //             height: size,
        //         );
        //         Uint8List recoded = image.encodePng(resizedImg);

        //         fwrite("${rpmPkgName}/usr/share/icons/hicolor/${size}x${size}/apps/${packageName}.png", recoded.toList());
        //     }
        // }

        // build package
        try {
            final buildRes = Process.runSync("rpmbuild", ["--define", "_topdir ${Directory("rpmbuild").absolute.path}", "-bb", "rpmbuild/SPECS/${packageName}.spec"]);
            printOutAndErrIfExist(buildRes);

            // move package to jvbuild-out and cleanup
            mv("rpmbuild/RPMS/${rpmArch}/${rpmPkgName}-1.${rpmArch}.rpm", "./jvbuild-out/${packageName}_${module.version}_${cpuArchToJvbuildArch[arch]!}.rpm");
        } catch (e) {
            print("jvbuild: Something went wrong while running rpmbuild\n${e}");
        }
        
        rm("rpmbuild");
    }
}
