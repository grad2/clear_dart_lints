import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/architecture/policy.dart';
import 'src/convert_to_block.dart';
import 'src/one_public_class_per_file.dart';
import 'src/rules.dart';
import 'src/rules/custom/avoid_nested_widget_ternaries.dart';
import 'src/rules/effective_dart/avoid_nullable_async_returns.dart';
import 'src/rules/effective_dart/avoid_nullable_collection_returns.dart';
import 'src/rules/effective_dart/avoid_public_late_final_fields.dart';
import 'src/rules/security/avoid_hardcoded_secrets.dart';

final plugin = ClearDartLintsPlugin();

class ClearDartLintsPlugin extends Plugin {
  @override
  String get name => 'clear_dart_lints';

  @override
  void register(PluginRegistry registry) {
    registry.registerWarningRule(ArchitecturePolicy());
    registry.registerLintRule(PreferBlockBodyForLongExpression());
    registry.registerLintRule(PreferBlockBodyForBuild());
    registry.registerLintRule(OnePublicClassPerFile());
    registry.registerLintRule(AvoidNestedWidgetTernaries());
    registry.registerLintRule(AvoidNullableCollectionReturns());
    registry.registerLintRule(AvoidNullableAsyncReturns());
    registry.registerLintRule(AvoidPublicLateFinalFields());
    registry.registerLintRule(AvoidHardcodedSecrets());
    registry.registerFixForRule(PreferBlockBodyForLongExpression.code, ConvertToBlock.new);
    registry.registerFixForRule(PreferBlockBodyForBuild.code, ConvertToBlock.new);
  }
}
