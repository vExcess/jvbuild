// https://wiki.debian.org/HowToPackageForDebian
// https://wiki.debian.org/Packaging/Intro

// https://specifications.freedesktop.org/desktop-entry-spec/latest/
// https://specifications.freedesktop.org/desktop-entry-spec/latest/recognized-keys.html

// https://www.redhat.com/en/blog/create-rpm-package

import 'dart:io';

import './JVModule.dart';
import './CommandArgs.dart';
import './packagers/deb.dart';
import './packagers/rpm.dart';

bool hasProgram(String desiredProgram) {
    final whereRes = Process.runSync("whereis", [desiredProgram]);
    final where = whereRes.stdout.toString();
    final locations = where
        .split(":")
        .sublist(1)
        .join(":")
        .split(" ")
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);
    
    for (final location in locations) {
        if (location.endsWith("/${desiredProgram}")) {
            return true;
        }
    }

    return false;
}

void package(JVModule module, CommandArgs args) async {
    if (hasProgram("dpkg-deb")) {
        print("\nPackaging as .deb");
        await DebPlugin().package(module, args);
    }

    if (hasProgram("rpmbuild")) {
        print("\nPackaging as .rpm");
        await RpmPlugin().package(module, args);
    }

    print("\nPackaging Complete!");
}
