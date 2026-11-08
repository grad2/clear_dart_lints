import 'package:clear_dart_lints/src/architecture/policy.dart';
import 'package:test/test.dart';

import 'new_rules_test.dart' show check;

const _policy = '''
schema_version: 2
include: ['main.dart', 'lib/**']
layers:
  data: ['main.dart', 'lib/**']
roles:
  dependency:
    names: ['*Datasource', '*DatasourceImpl', '*Repository', '*RepositoryImpl']
    libraries: ['main.dart', 'lib/**']
rules:
  layer_dependencies:
    allowed:
      - from: [data]
        to: [data]
        uris: ['dart:*', 'package:injectable/**']
  constructor_injection:
    source_layers: [data]
    dependency_roles: [dependency]
''';

const _files = {
  'lib/dependencies.dart': '''
class Transport { const Transport(); }
class Credentials { const Credentials(); }
abstract interface class OtherDatasource {}
class OtherDatasourceImpl implements OtherDatasource {}
Transport locateTransport() => const Transport();
OtherDatasource locateDatasource() => OtherDatasourceImpl();
final globalTransport = Transport();
''',
  'lib/annotations.dart': "export 'package:injectable/injectable.dart';",
};

Future<List<String>> _run(
  String source, {
  String annotationImport = "import 'package:injectable/injectable.dart';",
  List<String>? findings,
  String policy = _policy,
}) {
  final unit =
      '''
$annotationImport
import 'package:fixture/dependencies.dart';
$source
''';
  return check(
    ArchitecturePolicy(),
    unit,
    config: policy,
    files: _files,
    realPackages: true,
    requireValid: true,
    inspectDiagnostics: (diagnostics) {
      findings?.addAll(diagnostics.map((d) => unit.substring(d.offset, d.offset + d.length)));
    },
  );
}

void main() {
  group('Injectable forwarding factories', () {
    test(
      'arrow factory forwards required parameters to optional positional constructor inputs',
      () async {
        expect(
          await _run('''
@singleton
class ProbeDatasourceImpl {
  final Transport transport;
  final Credentials? credentials;
  ProbeDatasourceImpl(this.transport, [this.credentials]);
  @factoryMethod
  static ProbeDatasourceImpl injected(Transport transport, Credentials credentials) =>
      ProbeDatasourceImpl(transport, credentials);
}
'''),
          isEmpty,
        );
      },
    );

    test('block factory forwards named inputs and permits omitted null configuration', () async {
      expect(
        await _run('''
@singleton
class ProbeDatasourceImpl {
  final Transport transport;
  final Credentials? credentials;
  final String? publicRoot;
  ProbeDatasourceImpl(this.transport, {this.credentials, this.publicRoot});
  @factoryMethod
  static ProbeDatasourceImpl injected(Transport transport, Credentials credentials) {
    return ProbeDatasourceImpl(transport, credentials: credentials);
  }
}
'''),
        isEmpty,
      );
    });

    test(
      'resolved prefixed constructor annotation works through a re-export without singleton',
      () async {
        expect(
          await _run('''
class ProbeDatasourceImpl {
  final Transport transport;
  ProbeDatasourceImpl.named(this.transport);
  @di.FactoryMethod()
  static ProbeDatasourceImpl create({required Transport input}) =>
      ProbeDatasourceImpl.named((input));
}
''', annotationImport: "import 'package:fixture/annotations.dart' as di;"),
          isEmpty,
        );
      },
    );

    test('forwarded role-typed factory parameters are explicit injection', () async {
      expect(
        await _run('''
class ProbeDatasourceImpl {
  final OtherDatasource datasource;
  ProbeDatasourceImpl(this.datasource);
  @factoryMethod
  static ProbeDatasourceImpl create(OtherDatasource datasource) =>
      ProbeDatasourceImpl(datasource);
}
'''),
        isEmpty,
      );
    });

    test('layer restrictions still apply to forwarded factory parameters', () async {
      final result = await _run(
        '''
class ProbeDatasourceImpl {
  ProbeDatasourceImpl(Transport transport);
  @factoryMethod
  static ProbeDatasourceImpl create(Transport transport) => ProbeDatasourceImpl(transport);
}
''',
        policy: _policy.replaceFirst(
          "data: ['main.dart', 'lib/**']",
          "data: ['main.dart', 'lib/annotations.dart']\n  external: ['lib/dependencies.dart']",
        ),
      );
      expect(result, contains('layer_dependencies'));
      expect(result, isNot(contains('constructor_injection')));
    });

    test('role, contract and forbidden-symbol checks stay active in a verified factory', () async {
      final result = await _run(
        '''
class ProbeDatasourceImpl {
  ProbeDatasourceImpl(datasource);
  @factoryMethod
  static ProbeDatasourceImpl create(OtherDatasourceImpl datasource) =>
      ProbeDatasourceImpl(datasource);
}
''',
        policy: '''$_policy
  role_dependencies:
    restrictions:
      - source_layers: [data]
        dependency_roles: [dependency]
        allowed_consumer_roles: []
  depend_on_contracts:
    source_layers: [data]
    dependency_roles: [dependency]
  forbidden_symbols:
    source_layers: [data]
    symbols:
      - library: package:fixture/dependencies.dart
        name: OtherDatasourceImpl
''',
      );
      expect(
        result,
        containsAll(['role_dependencies', 'depend_on_contracts', 'forbidden_symbols']),
      );
      expect(result, isNot(contains('constructor_injection')));
    });

    test('ordinary consumer acquisition remains a warning', () async {
      final findings = <String>[];
      expect(
        await _run(
          '''
class BadConsumer {
  OtherDatasource make(Transport transport) => OtherDatasourceImpl();
}
''',
          annotationImport: '',
          findings: findings,
        ),
        ['constructor_injection'],
      );
      expect(findings, ['OtherDatasourceImpl()']);
    });

    test('singleton and a static method named injected do not establish a factory', () async {
      expect(
        await _run('''
@singleton
class ProbeDatasourceImpl {
  ProbeDatasourceImpl(Transport transport);
  static ProbeDatasourceImpl injected(Transport transport) => ProbeDatasourceImpl(transport);
}
'''),
        ['constructor_injection'],
      );
    });

    test('same-named local annotations do not establish Injectable identity', () async {
      expect(
        await _run('''
class FactoryMethod { const FactoryMethod(); }
const factoryMethod = FactoryMethod();
class ProbeDatasourceImpl {
  ProbeDatasourceImpl(Transport transport);
  @factoryMethod
  static ProbeDatasourceImpl injected(Transport transport) => ProbeDatasourceImpl(transport);
}
''', annotationImport: ''),
        ['constructor_injection'],
      );
    });

    test('real annotation on an instance method does not qualify', () async {
      expect(
        await _run('''
class ProbeDatasourceImpl {
  ProbeDatasourceImpl(Transport transport);
  @factoryMethod
  ProbeDatasourceImpl injected(Transport transport) => ProbeDatasourceImpl(transport);
}
'''),
        ['constructor_injection'],
      );
    });

    test('real annotation on a getter does not qualify', () async {
      expect(
        await _run('''
class ProbeDatasourceImpl {
  ProbeDatasourceImpl(Transport transport);
  @factoryMethod
  static ProbeDatasourceImpl get injected => ProbeDatasourceImpl(locateTransport());
}
'''),
        ['constructor_injection'],
      );
    });

    test('asynchronous factories are outside direct forwarding support', () async {
      expect(
        await _run('''
class ProbeDatasourceImpl {
  ProbeDatasourceImpl(Transport transport);
  @factoryMethod
  static Future<ProbeDatasourceImpl> injected(Transport transport) async =>
      ProbeDatasourceImpl(transport);
}
'''),
        ['constructor_injection'],
      );
    });

    test('real annotation does not allow constructing another datasource', () async {
      expect(
        await _run('''
class ProbeDatasourceImpl {
  @factoryMethod
  static OtherDatasourceImpl injected() => OtherDatasourceImpl();
}
'''),
        ['constructor_injection'],
      );
    });

    for (final argument in ['Transport()', 'locateTransport()', 'globalTransport']) {
      test('hidden input $argument does not qualify', () async {
        final findings = <String>[];
        expect(
          await _run('''
class ProbeDatasourceImpl {
  ProbeDatasourceImpl(Transport transport);
  @factoryMethod
  static ProbeDatasourceImpl injected(Transport transport) => ProbeDatasourceImpl($argument);
}
''', findings: findings),
          contains('constructor_injection'),
        );
        expect(findings, contains('ProbeDatasourceImpl($argument)'));
      });
    }

    test('foreign construction and locator calls inside a factory stay checked', () async {
      final findings = <String>[];
      expect(
        await _run('''
class ProbeDatasourceImpl {
  ProbeDatasourceImpl(Transport transport);
  @factoryMethod
  static ProbeDatasourceImpl injected(Transport transport) {
    OtherDatasourceImpl();
    locateDatasource();
    return ProbeDatasourceImpl(transport);
  }
}
''', findings: findings),
        everyElement('constructor_injection'),
      );
      expect(
        findings,
        containsAll([
          'OtherDatasourceImpl()',
          'locateDatasource()',
          'ProbeDatasourceImpl(transport)',
        ]),
      );
    });

    test('nested dependency acquisition in a constructor argument stays checked', () async {
      final findings = <String>[];
      expect(
        await _run('''
class ProbeDatasourceImpl {
  ProbeDatasourceImpl(OtherDatasource datasource);
  @factoryMethod
  static ProbeDatasourceImpl injected() => ProbeDatasourceImpl(locateDatasource());
}
''', findings: findings),
        everyElement('constructor_injection'),
      );
      expect(
        findings,
        containsAll(['locateDatasource()', 'ProbeDatasourceImpl(locateDatasource())']),
      );
    });

    test('optional factory input with a default does not qualify', () async {
      expect(
        await _run('''
class ProbeDatasourceImpl {
  ProbeDatasourceImpl(Transport transport);
  @factoryMethod
  static ProbeDatasourceImpl injected([Transport transport = const Transport()]) =>
      ProbeDatasourceImpl(transport);
}
'''),
        ['constructor_injection'],
      );
    });

    test('duplicated input and unused factory parameter do not qualify', () async {
      expect(
        await _run('''
class ProbeDatasourceImpl {
  ProbeDatasourceImpl(Transport first, Transport second);
  @factoryMethod
  static ProbeDatasourceImpl injected(Transport first, Transport second) =>
      ProbeDatasourceImpl(first, first);
}
'''),
        ['constructor_injection'],
      );
    });

    test('omitted non-null constructor defaults do not qualify', () async {
      expect(
        await _run('''
class ProbeDatasourceImpl {
  ProbeDatasourceImpl(Transport transport, [Credentials credentials = const Credentials()]);
  @factoryMethod
  static ProbeDatasourceImpl injected(Transport transport) => ProbeDatasourceImpl(transport);
}
'''),
        ['constructor_injection'],
      );
    });

    test('factory constructors cannot redirect creation to another implementation', () async {
      expect(
        await _run('''
class ProbeDatasourceImpl {
  factory ProbeDatasourceImpl(Transport transport) = _OtherDatasourceImpl;
  @factoryMethod
  static ProbeDatasourceImpl injected(Transport transport) => ProbeDatasourceImpl(transport);
}
class _OtherDatasourceImpl implements ProbeDatasourceImpl {
  _OtherDatasourceImpl(Transport transport);
}
'''),
        ['constructor_injection'],
      );
    });
  });
}
