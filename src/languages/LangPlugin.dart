import '../JVModule.dart';
import '../CommandArgs.dart';

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
