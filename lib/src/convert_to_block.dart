import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';

import 'body_utils.dart';

class ConvertToBlock extends ResolvedCorrectionProducer {
  ConvertToBlock({required super.context});

  @override
  CorrectionApplicability get applicability => CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind =>
      const FixKind('clear_dart_lints.fix.convertToBlock', 50, 'Convert to block body');

  @override
  Future<void> compute(ChangeBuilder builder) async {
    AstNode? target = node;
    while (target != null && target is! ExpressionFunctionBody) {
      target = target.parent;
    }
    if (target is! ExpressionFunctionBody) return;
    final original = unitResult.content;
    final updated = convertToBlock(
      target,
      original,
      pageWidth: pageWidthFor(unitResult),
      returnsVoid: discardsResult(target),
    );
    var start = 0;
    while (start < original.length &&
        start < updated.length &&
        original.codeUnitAt(start) == updated.codeUnitAt(start)) {
      start++;
    }
    var oldEnd = original.length;
    var newEnd = updated.length;
    while (oldEnd > start &&
        newEnd > start &&
        original.codeUnitAt(oldEnd - 1) == updated.codeUnitAt(newEnd - 1)) {
      oldEnd--;
      newEnd--;
    }
    if (oldEnd == start && newEnd == start) return;
    await builder.addDartFileEdit(file, (edit) {
      edit.addSimpleReplacement(
        SourceRange(start, oldEnd - start),
        updated.substring(start, newEnd),
      );
    });
  }
}
