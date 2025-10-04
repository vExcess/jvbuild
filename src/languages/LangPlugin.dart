import '../BuildDefinition.dart';
import '../JVModule.dart';

class CommandArgs {
    String outputPath;
    String optimizationLevel; // will be "default" if not user specified
    String selector; // will be "default" if not user specified
    bool isVerbose;
    BuildDefinition buildDef;

    CommandArgs({
        required this.outputPath,
        required this.optimizationLevel,
        required this.selector,
        required this.isVerbose,
        required this.buildDef,
    });
}

class LangPlugin {
    Future<void> build(JVModule module, CommandArgs args) async {
        throw "LangPlugin.build must be implemented by child";
    }

    Future<void> run(JVModule module, CommandArgs args) async {
        throw "LangPlugin.run must be implemented by child";
    }

    String? translate(JVModule module, CommandArgs args) {
        throw "LangPlugin.translate must be implemented by child";
    }
}
