import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models.dart';

class AppDatabase extends GeneratedDatabase {
  AppDatabase(super.executor);
  static Future<AppDatabase> open() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return AppDatabase(
      NativeDatabase.createInBackground(
        File(p.join(directory.path, 'az_utility.sqlite')),
      ),
    );
  }

  @override
  int get schemaVersion => 3;
  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE records (id INTEGER PRIMARY KEY AUTOINCREMENT, category TEXT NOT NULL, title TEXT NOT NULL, created TEXT NOT NULL, payload TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE INDEX records_category_date ON records(category, created DESC)',
      );
      await _createIndexTable();
      await _createMonitoring();
    },
    onUpgrade: (_, from, to) async {
      if (from < 2) await _createIndexTable();
      if (from < 3) await _createMonitoring();
    },
  );
  Future<void> _createMonitoring() => customStatement(
    'CREATE TABLE monitor_samples (created TEXT NOT NULL, label TEXT NOT NULL, ratio REAL NOT NULL)',
  );
  Future<void> _createIndexTable() => customStatement(
    'CREATE TABLE indexed_files (path TEXT PRIMARY KEY, size INTEGER NOT NULL, modified TEXT NOT NULL, category TEXT NOT NULL)',
  );
  Future<void> saveIndex(List<IndexedFile> files) => transaction(() async {
    await customStatement('DELETE FROM indexed_files');
    await batch((b) {
      for (final file in files) {
        b.customStatement('INSERT INTO indexed_files VALUES (?,?,?,?)', [
          file.path,
          file.size,
          file.modified.toIso8601String(),
          file.category,
        ]);
      }
    });
  });
  Future<List<IndexedFile>> loadIndex() async =>
      (await customSelect('SELECT * FROM indexed_files LIMIT 100000').get())
          .map(
            (row) => IndexedFile(
              row.read<String>('path'),
              row.read<int>('size'),
              DateTime.parse(row.read<String>('modified')),
              row.read<String>('category'),
            ),
          )
          .toList();
  Future<Map<String, dynamic>> settings() async => {
    for (final row in await customSelect('SELECT * FROM settings').get())
      row.read<String>('key'): jsonDecode(row.read<String>('value')),
  };
  Future<void> set(String key, dynamic value) => customStatement(
    'INSERT OR REPLACE INTO settings(key,value) VALUES (?,?)',
    [key, jsonEncode(value)],
  );
  Future<void> resetSettings() => customStatement('DELETE FROM settings');

  Future<void> prune(int days, {DateTime? now}) async {
    if (days < 1 || days > 3650) {
      throw ArgumentError('Invalid retention period');
    }
    await customStatement('DELETE FROM records WHERE created < ?', [
      (now ?? DateTime.now())
          .toUtc()
          .subtract(Duration(days: days))
          .toIso8601String(),
    ]);
    await customStatement('DELETE FROM monitor_samples WHERE created < ?', [
      (now ?? DateTime.now())
          .toUtc()
          .subtract(Duration(days: days))
          .toIso8601String(),
    ]);
  }

  Future<void> saveMonitoring(List<Metric> metrics) => transaction(() async {
    for (final metric in metrics.where((m) => m.ratio != null)) {
      await customStatement('INSERT INTO monitor_samples VALUES (?,?,?)', [
        DateTime.now().toUtc().toIso8601String(),
        metric.label,
        metric.ratio,
      ]);
    }
    await customStatement(
      'DELETE FROM monitor_samples WHERE rowid NOT IN (SELECT rowid FROM monitor_samples ORDER BY rowid DESC LIMIT 10000)',
    );
  });

  Future<List<Map<String, dynamic>>> monitoring() async =>
      (await customSelect(
            'SELECT * FROM monitor_samples ORDER BY rowid DESC LIMIT 10000',
          ).get())
          .map(
            (r) => {
              'created': r.read<String>('created'),
              'label': r.read<String>('label'),
              'ratio': r.read<double>('ratio'),
            },
          )
          .toList();
  Future<void> save(String category, String title, dynamic payload) async {
    await customStatement(
      'INSERT INTO records(category,title,created,payload) VALUES (?,?,?,?)',
      [
        category,
        title,
        DateTime.now().toUtc().toIso8601String(),
        jsonEncode(payload),
      ],
    );
    await customStatement(
      'DELETE FROM records WHERE category=? AND id NOT IN (SELECT id FROM records WHERE category=? ORDER BY id DESC LIMIT 500)',
      [category, category],
    );
  }

  Future<List<Map<String, dynamic>>> history({
    String? category,
    int limit = 100,
  }) async {
    final rows = await customSelect(
      'SELECT * FROM records ${category == null ? '' : 'WHERE category=?'} ORDER BY id DESC LIMIT ?',
      variables: [
        if (category != null) Variable<String>(category),
        Variable<int>(limit),
      ],
    ).get();
    return rows
        .map(
          (r) => {
            'id': r.read<int>('id'),
            'category': r.read<String>('category'),
            'title': r.read<String>('title'),
            'created': r.read<String>('created'),
            'payload': jsonDecode(r.read<String>('payload')),
          },
        )
        .toList();
  }

  Future<void> clear(String category) => transaction(() async {
    await customStatement('DELETE FROM records WHERE category=?', [category]);
    if (category == 'files') {
      await customStatement('DELETE FROM indexed_files');
      await customStatement("DELETE FROM settings WHERE key='safLatestIndex'");
    }
    if (category == 'device') {
      await customStatement('DELETE FROM monitor_samples');
    }
  });
}
