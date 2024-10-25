import 'dart:async';
import 'dart:io';

const PACKAGE_NAME = "jvbuild";
const PACKAGE_VERSION = "0.0.1";
const PACKAGE_AUTHOR = "VExcess <github.com/vExcess>";
const PACKAGE_DESCRIPTION = """
    Cross platform, language agnostic build
    system
""";

void main() async {
    final res = await Process.run("dart", ["compile", "exe", "./src/${PACKAGE_NAME}.dart"]);
    print(res.stdout);

    final EXE_FILE_PATH = "./src/${PACKAGE_NAME}.exe";
    final fileSize = (await File(EXE_FILE_PATH).length()) / 1024;

    var splitted = PACKAGE_DESCRIPTION.trim().split("\n");
    for (var i = 0; i < splitted.length; i++) {
        splitted[i] = " " + splitted[i].trim();
    }

    final debMetadata = File("deb-metadata.yaml");
    await debMetadata.writeAsString("""Package: ${PACKAGE_NAME}
Version: ${PACKAGE_VERSION}
Installed-Size: ${fileSize.round()}
Section: base
Priority: optional
Architecture: i386
Depends: 
Maintainer: ${PACKAGE_AUTHOR}
Description: ${PACKAGE_NAME}
${splitted.join("\n")}
""");

    final bashScript = File("build.sh");
    final debPkgName = "${PACKAGE_NAME}_${PACKAGE_VERSION}";
    await bashScript.writeAsString("""
# move to dist
mkdir ./dist || true;
mv ${EXE_FILE_PATH} ./dist/${PACKAGE_NAME}

# setup deb filetree
rm $debPkgName -r || true
mkdir $debPkgName
mkdir $debPkgName/usr
mkdir $debPkgName/usr/local
mkdir $debPkgName/usr/local/bin

# copy over compiled binaries
cp ./dist/${PACKAGE_NAME} $debPkgName/usr/local/bin/${PACKAGE_NAME}

# build package and cleanup
mkdir $debPkgName/DEBIAN
cp ./deb-metadata.yaml $debPkgName/DEBIAN/control
dpkg-deb --build $debPkgName
mv ./$debPkgName.deb ./dist/$debPkgName.deb
rm -r $debPkgName

rm ./build.sh
rm ./deb-metadata.yaml
""");

    final res2 = await Process.run("bash", ["build.sh"]);
    print(res2.stdout);

}
