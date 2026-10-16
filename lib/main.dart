import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/convert_to_block.dart';
import 'src/rules.dart';
import 'src/one_public_class_per_file.dart';

final plugin = ClearDartLintsPlugin();

class ClearDartLintsPlugin extends Plugin {
  @override
  String get name => 'clear_dart_lints';

  @override
  void register(PluginRegistry registry) {
    registry.registerLintRule(PreferBlockBodyForLongExpression());
    registry.registerLintRule(PreferBlockBodyForBuild());
    registry.registerLintRule(OnePublicClassPerFile());
    registry.registerFixForRule(PreferBlockBodyForLongExpression.code, ConvertToBlock.new);
    registry.registerFixForRule(PreferBlockBodyForBuild.code, ConvertToBlock.new);
  }
}
