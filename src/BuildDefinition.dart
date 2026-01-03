import 'dart:io';

import 'package:json5/json5.dart';

import './JVModule.dart';
import './utils.dart';

bool isValidModuleName(String name) {
    for (int i = 0; i < name.length; i++) {
        final ch = name.codeUnitAt(i);
        if (!(
            // is uppercase
            (ch >= 65 && ch <= 90) ||
            // is lowercase
            (ch >= 97 && ch <= 122) ||
            // is number
            (ch >= 48 && ch <= 57) ||
            // is underscore or dash
            ch == 95 || ch == 45)
        ) {
            return false;
        }
    }
    return true;
}

List<String>? parseDependencies(dynamic json, BuildDefinition buildDef) {
    if (json == null) {
        return [];
    }

    List<Object> dependencies;
    if (assertArr<Object>(json)) {
        dependencies = castArr<Object>(json);
    } else {
        print("jvbuild: invalid dependencies: ${json}");
        return null;
    }
    
    for (int i = 0; i < dependencies.length; i++) {
        final dependencyJSON = dependencies[i];
        if (dependencyJSON is Map<String, dynamic>) {
            final module = parseModule(dependencyJSON, buildDef);
            if (module == null) return null;

            buildDef.modules[module.name] = module;
            dependencies[i] = module.name;
        } else if (dependencyJSON is! String) {
            print("jvbuild: invalid module definition: ${dependencyJSON}");
            return null;
        }
    }
    return castArr<String>(dependencies);
}

JVModule? parseModule(Map<String, dynamic> moduleJSON, BuildDefinition buildDef) {
    final name = assertType<String?>(moduleJSON["name"]);
    if (name == null || !isValidModuleName(name)) {
        print("jvbuild: invalid name: ${name}");
        return null;
    }
    
    var root = assertType<String?>(moduleJSON["root"]);
    var include = assertType<String?>(moduleJSON["include"]);
    var lib_path = assertType<String?>(moduleJSON["lib_path"]);
    var modTypeString = assertType<String?>(moduleJSON["type"]);
    List<String> typeParts = [];

    if (modTypeString == null) {
        if (root == null) {
            print("jvbuild: type and root cannot both be excluded");
            return null;
        } else {
            typeParts = [root.split(".").reversed.first, "exe"];
        }
    } else {
        typeParts = modTypeString.split(":");
    }
    
    final language = typeParts[0];
    ModuleType modType = switch (typeParts[1]) {
        "exe" => ModuleType.EXE,
        "lib" => ModuleType.LIB,
        _ => ModuleType.UNRESOLVED
    };
    if (language != "system" && modType == ModuleType.UNRESOLVED) {
        print("jvbuild: unknown module type");
        return null;
    }

    Map<String, String> install = {};
    if (assertMap<String, String>(moduleJSON["install"])) {
        install = castMap<String, String>(moduleJSON["install"]);
    }
    final dependencies = parseDependencies(moduleJSON["dependencies"], buildDef);
    final devDependencies = parseDependencies(moduleJSON["dev_dependencies"], buildDef);

    if (root != null) {
        root = Uri.file(buildDef.filePath).resolve(root).toString().substring("file://".length);
    }
    if (include != null) {
        include = Uri.file(buildDef.filePath).resolve(include).toString().substring("file://".length);
    }
    if (lib_path != null) {
        lib_path = Uri.file(buildDef.filePath).resolve(lib_path).toString().substring("file://".length);
    }

    final version = assertType<String?>(moduleJSON["version"]);

    return JVModule(
        name: name,
        language: language,
        modType: modType,
        version: version,
        root: root,
        include: include,
        lib_path: lib_path,
        install: install,
        dependencies: dependencies,
        devDependencies: devDependencies,
        buildFilePath: buildDef.filePath
    );
}

void parseModules(Map<String, dynamic> jsonModules, BuildDefinition buildDef) {
    for (final itemName in jsonModules.keys) {
        // not an import
        if (itemName[0] != "\$") {
            // get module json
            final moduleJSON = jsonModules[itemName];
            if (moduleJSON is! Map<String, dynamic>) {
                print("jvbuild: invalid module contents: ${itemName}");
                return;
            }

            // parse module json
            moduleJSON["name"] = itemName;
            final module = parseModule(moduleJSON, buildDef);
            if (module == null) return;

            // store module
            buildDef.modules[module.name] = module;
        }
    }
}

class BuildDefinition {
    String name = "";
    String description = "";
    String author = "";
    String repository = "";
    String license = "";

    String? genericName;
    String? icon;
    List<String> categories = [];
    List<String> keywords = [];
    List<String> mimeType = [];

    String? defaultModule;

    Map<String, JVModule> modules = {};
    Map<String, List<String>> build = {};
    Map<String, String> run = {};

    String filePath = "";
    List<String> remoteImportLinks = [];

    BuildDefinition({
        required this.name,
        String? description,
        String? author,
        String? repository,
        String? license,
        this.defaultModule,
        required this.modules,
        Map<String, List<String>>? build,
        Map<String, String>? run,

        this.icon,
        this.genericName,
        List<String>? categories,
        List<String>? keywords,
        List<String>? mimeType,
    }) {
        if (description != null) this.description = description;
        if (author != null) this.author = author;
        if (repository != null) this.repository = repository;
        if (license != null) this.license = license;
        if (build != null) this.build = build;
        if (run != null) this.run = run;
        if (categories != null) this.categories = categories;
        if (keywords != null) this.keywords = keywords;
        if (mimeType != null) this.mimeType = mimeType;
    }

    static Future<BuildDefinition?> parseBuildFile(String filePath, bool isEntrypoint) async {
        final file = File(filePath);
        
        if (file.existsSync()) {
            // read file contents
            final contents = file.readAsStringSync();
            dynamic parsed;
            try {
                parsed = JSON5.parse(contents);
            } catch (e) {
                print("jvbuild: invalid json5 file\n\t${e}\n${contents}");
                return null;
            }

            final buildSpec = assertMap<String, dynamic>(parsed) ? parsed : null;
            if (buildSpec == null) {
                print("jvbuild: invalid json5 file contents");
                return null;
            }

            // convert build from json to structured
            var dynamicBuild = buildSpec["build"];
            Map<String, List<String>> buildModes = {};
            if (dynamicBuild != null) {
                for (final prop in dynamicBuild.keys) {
                    List<String> temp = [];
                    final buildModesList = dynamicBuild[prop];
                    if (buildModesList is List<dynamic>) {
                        for (var i = 0; i < buildModesList.length; i++) {
                            final item = buildModesList[i];
                            if (item is String) {
                                temp.add(item);
                            } else {
                                print("jvbuild: invalid contents parsing build: ${buildModesList}");
                                return null;
                            }
                        }
                        buildModes[prop] = temp;
                    } else {
                        print("jvbuild: invalid contents parsing build: ${buildModesList}");
                        return null;
                    }
                }
            }

            // convert run from json to structured
            var dynamicRun = buildSpec["run"];
            Map<String, String> runScripts = {};
            if (dynamicRun != null) {
                for (final prop in dynamicRun.keys) {
                    final item = dynamicRun[prop];
                    if (item is String){
                        runScripts[prop as String] = item;
                    } else {
                        print("jvbuild: invalid contents parsing build: ${dynamicRun[prop]}");
                        return null;
                    }
                }
            }

            BuildDefinition buildDef;
            try {
                if (buildSpec["name"] == null) {
                    print("jvbuild: project name is required");
                    return null;
                }
                final name = assertType<String>(buildSpec["name"]);
                final description = assertType<String?>(buildSpec["description"]);
                final author = assertType<String?>(buildSpec["author"]);
                final repository = assertType<String?>(buildSpec["repository"]);
                final license = assertType<String?>(buildSpec["license"]);
                final defaultModule = assertType<String?>(buildSpec["default"]);

                final genericName = assertType<String?>(buildSpec["genericName"]);
                final categories = assertArr<String>(buildSpec["categories"]) ? castArr<String>(buildSpec["categories"]) : null;
                final keywords = assertArr<String>(buildSpec["keywords"]) ? castArr<String>(buildSpec["keywords"]) : null;
                final mimeType = assertArr<String>(buildSpec["mimeType"]) ? castArr<String>(buildSpec["mimeType"]) : null;
                final icon = assertType<String?>(buildSpec["icon"]);

                if (defaultModule != null) {
                    buildModes[defaultModule] = [defaultModule];
                }

                buildDef = BuildDefinition(
                    name: name,
                    description: description,
                    author: author,
                    repository: repository,
                    license: license,
                    defaultModule: defaultModule,
                    modules: {},
                    build: buildModes,
                    run: runScripts,

                    genericName: genericName,
                    categories: categories,
                    keywords: keywords,
                    mimeType: mimeType,
                    icon: icon
                );
                buildDef.filePath = file.absolute.path;
            } catch (e) {
                print("ERR: ${e}");
                return null;
            }

            // parse modules
            final jsonModules = buildSpec["modules"];
            if (jsonModules == null || jsonModules is! Map<String, dynamic>) {
                print("jvbuild: build definition not found or is invalid");
                return null;
            } else {
                parseModules(jsonModules, buildDef);

                final subJSONModules = jsonModules["\$importAll"];
                if (subJSONModules is List) {
                    for (var i = 0; i < subJSONModules.length; i++) {
                        final importStatement = subJSONModules[i];
                        if (!assertMap<String, String>(importStatement)) {
                            print("jvbuild: invalid import statement: ${importStatement}");
                            return null;
                        }

                        final local = importStatement["local"];
                        final remote = importStatement["remote"];

                        // find buildDef directory
                        var buildDefDirPath = buildDef.filePath;
                        var backWalk = buildDefDirPath.length - 1;
                        while (backWalk >= 0 && buildDefDirPath[backWalk] != '/') {
                            backWalk--;
                        }
                        buildDefDirPath = buildDefDirPath.substring(0, backWalk + 1);

                        var localModDirExists = false;
                        if (local is String) {
                            String localBuildPath;
                            if (local.startsWith("/")) {
                                localBuildPath = local;
                            } else {
                                localBuildPath = buildDefDirPath + local;
                            }
                            if (localBuildPath.endsWith("/")) {
                                localBuildPath = localBuildPath.substring(0, localBuildPath.length - 1);
                            }
                            if (!localBuildPath.endsWith("build.json5")) {
                                localBuildPath = localBuildPath + "/build.json5";
                            }

                            final localBuildFile = File(localBuildPath);
                            if (localBuildFile.existsSync()) {
                                localModDirExists = true;

                                // import sub modules
                                final res = await parseBuildFile(localBuildPath, false);
                                if (res != null) {
                                    for (final moduleName in res.modules.keys) {
                                        if (!buildDef.modules.containsKey(moduleName)) {
                                            buildDef.modules[moduleName] = res.modules[moduleName]!;
                                        }
                                    }
                                }
                            }
                        }
                        
                        if (!localModDirExists && remote is String) {
                            final downloadName = "download-" + remote
                                .replaceFirst("https://", "")
                                .replaceFirst("http://", "")
                                .replaceAll("/", "_");
                            final unzipPath = "./jvbuild-cache/${downloadName}";
                            
                            var unzipDir = Directory(unzipPath);
                            if (unzipDir.existsSync()) {
                                var modBuildFile = await getCachedBuildFile(unzipPath);
                                if (modBuildFile != null) {
                                    // import cached remote modules
                                    final res = await parseBuildFile(modBuildFile.absolute.path, false);
                                    if (res != null) {
                                        for (final moduleName in res.modules.keys) {
                                            // print("AAA");
                                            // print(moduleName);
                                            if (!buildDef.modules.containsKey(moduleName)) {
                                                buildDef.modules[moduleName] = res.modules[moduleName]!;
                                            }
                                        }
                                    }
                                }
                            }

                            buildDef.remoteImportLinks.add(remote);
                        }
                    }
                }
            }

            return buildDef;
        } else {
            print("jvbuild: file not found [${filePath}](${file.absolute.path})");
            return null;
        }
    }

    String toString() {
        return """{
    name: ${name},
    description: ${description},
    author: ${author},
    repository: ${repository},
    license: ${license},
    modules: ${modules},
    build: ${build},
    run: ${run},
}""";
    }
}
