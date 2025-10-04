enum ModuleType {
    UNRESOLVED,
    EXE,
    LIB
}

class JVModule {
    String name = "";
    String language = "";
    ModuleType modType = ModuleType.UNRESOLVED;
    String version = "0.0.0";
    String root = "";
    Map<String, String> install = {};
    List<String> dependencies = [];
    List<String> devDependencies = [];

    String buildFilePath;

    JVModule({
        String? name,
        required this.language,
        required this.modType,
        String? version,
        String? root,
        Map<String, String>? install,
        List<String>? dependencies,
        List<String>? devDependencies,
        required this.buildFilePath,
    }) {
        if (name != null) this.name = name;
        if (version != null) this.version = version;
        if (root != null) this.root = root;
        if (install != null) this.install = install;
        if (dependencies != null) this.dependencies = dependencies;
        if (devDependencies != null) this.devDependencies = devDependencies;
    }

    // void propogateDependencies(List<JVModule> modules) {
    //     final deps = this.dependencies;
    //     List<String> sysDeps = [];
    //     for (var i = 0; i < deps.length; i++) {
    //         final depMod = findOne(modules, (mod) => mod.name == deps[i]);
    //         if (depMod != null) {
    //             depMod.propogateDependencies(modules);

    //             // move up system dependencies
    //             for (var j = 0; j < depMod.sysLibraries.length; j++) {
    //                 final sysLib = depMod.sysLibraries[j];
    //                 if (!this.sysLibraries.contains(sysLib)) {
    //                     this.sysLibraries.add(sysLib);
    //                 }
    //             }

    //             // move up libc
    //             if (depMod.linkLibC) {
    //                 this.linkLibC = true;
    //             }
    //         } else {
    //             print("jvbuild: failed to locate module ${deps[i]}");
    //         }
    //     }

    //     // link libc
    //     for (var i = 0; i < this.sysLibraries.length; i++) {
    //         if (this.sysLibraries[i] == "libc") {
    //             this.linkLibC = true;
    //             this.sysLibraries.removeAt(i);
    //             break;
    //         }
    //     }
    // }

    String toString() {
        return """{
    name: ${name},
    language: ${language},
    modType: ${modType},
    version: ${version},
    root: ${root},
    install: ${install},
    dependencies: ${dependencies},
    devDependencies: ${devDependencies},
}""";
    }
}
