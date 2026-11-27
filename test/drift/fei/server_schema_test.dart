// Checks that server/schema.sql has the same tables, columns, nullability and
// indexes as the newest drift schema snapshot, so sync rows fit both sides.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';

void main() {
  test('server/schema.sql matches the newest drift schema', () {
    final version = GeneratedHelper.versions.last;
    final drift = jsonDecode(File('drift_schemas/fei/drift_schema_v$version.json').readAsStringSync());
    final entities = [for (final e in drift['entities'] as List) e as Map<String, dynamic>];

    final driftTables = {
      for (final e in entities.where((e) => e['type'] == 'table'))
        e['data']['name'] as String: {
          for (final c in e['data']['columns'] as List) c['name'] as String: c['nullable'] as bool,
        },
    };
    final driftIndexes = {for (final e in entities.where((e) => e['type'] == 'index')) e['data']['name'] as String};

    final sql = File('server/schema.sql').readAsStringSync().replaceAll(RegExp(r'--.*'), '');
    final serverTables = {
      for (final m in RegExp(r'CREATE TABLE (\w+) \((.*?)\n\);', dotAll: true).allMatches(sql))
        m[1]!: {
          for (final line in m[2]!.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty))
            line.split(RegExp(r'\s+')).first: !line.contains('NOT NULL') && !line.contains('PRIMARY KEY'),
        },
    };
    final serverIndexes = {for (final m in RegExp(r'CREATE INDEX (\w+)').allMatches(sql)) m[1]!};

    expect(serverTables, driftTables);
    expect(serverIndexes, driftIndexes);
  });
}
