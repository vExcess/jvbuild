import './BuildDefinition.dart';

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