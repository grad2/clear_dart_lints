import 'package:clear_dart_lints/src/agent_tools/cli.dart';

/// Audits setup and suppression policy; architecture is checked by dart analyze.
Future<void> main(List<String> arguments) => runAgentTool('verify_setup', arguments);
