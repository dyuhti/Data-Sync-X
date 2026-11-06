import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:datasyncx/database/local_db.dart';
import 'package:datasyncx/models/change_log.dart';
import 'package:datasyncx/models/conflict.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late LocalDatabase database;
  late String databasePath;

  setUpAll(() async {
    databasePath = join(
      await getDatabasesPath(),
      'conflict-storage-test-${DateTime.now().microsecondsSinceEpoch}.db',
    );
    final versionTwoDatabase = await openDatabase(
      databasePath,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE notes (
            id TEXT PRIMARY KEY NOT NULL,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            version INTEGER NOT NULL,
            updated_at TEXT NOT NULL,
            sync_status TEXT NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE change_log (
            id TEXT PRIMARY KEY NOT NULL,
            record_id TEXT NOT NULL,
            operation TEXT NOT NULL,
            base_version INTEGER NOT NULL,
            version INTEGER NOT NULL,
            timestamp TEXT NOT NULL,
            payload TEXT NOT NULL,
            synced INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.insert('notes', {
          'id': 'migration-note',
          'title': 'Existing note',
          'content': 'Preserve me',
          'version': 1,
          'updated_at': '2026-11-06T10:00:00.000Z',
          'sync_status': 'synced',
          'is_deleted': 0,
        });
        await db.insert('change_log', {
          'id': 'migration-change',
          'record_id': 'migration-note',
          'operation': 'CREATE',
          'base_version': 0,
          'version': 1,
          'timestamp': '2026-11-06T10:00:00.000Z',
          'payload': '{"id":"migration-note"}',
          'synced': 1,
        });
      },
    );
    await versionTwoDatabase.close();
    database = LocalDatabase.forTesting(databasePath);
    await database.initialize();
  });

  tearDownAll(() async {
    await database.close();
    await deleteDatabase(databasePath);
  });

  test('conflict model decodes and serializes JSON payloads', () {
    final detectedAt = DateTime.utc(2026, 11, 6, 10, 0);
    final conflict = Conflict(
      conflictId: 'conflict-1',
      recordId: 'record-1',
      conflictType: ConflictType.updateUpdate,
      operation: 'UPDATE',
      localVersion: 2,
      remoteVersion: 2,
      localPayload: {'content': 'local'},
      remotePayload: {'content': 'remote'},
      detectedAt: detectedAt,
    );

    final restored = Conflict.fromJson(conflict.toJson());

    expect(restored.localPayload['content'], 'local');
    expect(restored.remotePayload['content'], 'remote');
    expect(restored.detectedAt, detectedAt);
    expect(restored.conflictType, ConflictType.updateUpdate);
    expect(restored.resolutionStatus, ResolutionStatus.unresolved);
  });

  test(
    'database migration preserves existing data and adds resolution storage',
    () async {
      final sqlite = await database.database;
      final tables = await sqlite.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN "
        "('notes', 'change_log', 'conflicts', 'conflict_changes')",
      );
      final tableNames = tables.map((row) => row['name']).toSet();

      expect(
        tableNames,
        containsAll(['notes', 'change_log', 'conflicts', 'conflict_changes']),
      );
      expect(
        (await database.getAllNotes()).any(
          (note) => note.id == 'migration-note',
        ),
        isTrue,
      );
      expect(
        (await database.getAllChanges()).any(
          (change) => change.id == 'migration-change',
        ),
        isTrue,
      );
      final migrationChange = (await database.getAllChanges()).firstWhere(
        (change) => change.id == 'migration-change',
      );
      expect(migrationChange.effectiveState, ChangeLogState.synced);

      final indexes = await sqlite.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name IN "
        "('idx_conflicts_record_id', 'idx_conflicts_resolution_status', "
        "'idx_conflicts_unresolved_identity')",
      );
      expect(indexes, hasLength(3));
    },
  );

  test('stores, reads, deduplicates, and resolves conflicts', () async {
    final recordId = 'record-${DateTime.now().microsecondsSinceEpoch}';
    final localPayload = {'id': recordId, 'content': 'local'};
    final remotePayload = {'id': recordId, 'content': 'remote'};
    final detectedAt = DateTime.utc(2026, 11, 6, 10, 1);

    final inserted = await database.insertConflict(
      recordId: recordId,
      conflictType: ConflictType.updateUpdate,
      operation: 'UPDATE',
      localVersion: 2,
      remoteVersion: 2,
      localPayload: localPayload,
      remotePayload: remotePayload,
      detectedAt: detectedAt,
    );
    final duplicate = await database.insertConflict(
      recordId: recordId,
      conflictType: ConflictType.updateUpdate,
      operation: 'UPDATE',
      localVersion: 2,
      remoteVersion: 2,
      localPayload: {'content': 'different duplicate'},
      remotePayload: {'content': 'different duplicate'},
    );

    expect(duplicate.conflictId, inserted.conflictId);
    expect(
      await database.getUnresolvedConflictCount(),
      greaterThanOrEqualTo(1),
    );
    expect(
      (await database.getUnresolvedConflicts()).any(
        (conflict) => conflict.conflictId == inserted.conflictId,
      ),
      isTrue,
    );
    expect(
      (await database.getConflictsForRecord(recordId)).single.localPayload,
      localPayload,
    );
    expect(
      (await database.getConflictById(inserted.conflictId))!.remotePayload,
      remotePayload,
    );

    await database.markConflictResolved(inserted.conflictId);
    expect(
      (await database.getConflictById(inserted.conflictId))!.resolutionStatus,
      ResolutionStatus.resolved,
    );
    expect(
      (await database.getUnresolvedConflicts()).any(
        (conflict) => conflict.conflictId == inserted.conflictId,
      ),
      isFalse,
    );

    final repeatedAfterResolution = await database.insertConflict(
      recordId: recordId,
      conflictType: ConflictType.updateUpdate,
      operation: 'UPDATE',
      localVersion: 2,
      remoteVersion: 2,
      localPayload: localPayload,
      remotePayload: remotePayload,
    );
    expect(repeatedAfterResolution.conflictId, isNot(inserted.conflictId));
    expect(await database.getConflictsForRecord(recordId), hasLength(2));
  });

  Future<Conflict> createResolutionFixture({
    required String suffix,
    ConflictType type = ConflictType.updateUpdate,
    String operation = 'UPDATE',
    int localVersion = 2,
    int remoteVersion = 2,
  }) async {
    final note = await database.insertNote(
      title: 'Local $suffix',
      content: 'Local content $suffix',
    );
    final create = (await database.getPendingChanges()).lastWhere(
      (change) => change.recordId == note.id,
    );
    await database.markChangesAsSynced([create.id]);
    await database.updateNote(
      note,
      title: 'Changed $suffix',
      content: 'Changed content $suffix',
    );
    final change = (await database.getPendingChanges()).lastWhere(
      (item) => item.recordId == note.id,
    );
    expect(change.version, localVersion);
    return database.insertConflict(
      recordId: note.id,
      conflictType: type,
      operation: operation,
      localVersion: localVersion,
      remoteVersion: remoteVersion,
      localPayload: {
        'id': note.id,
        'title': 'Changed $suffix',
        'content': 'Changed content $suffix',
        'version': localVersion,
        'updated_at': '2026-11-06T10:00:00.000Z',
        'is_deleted': false,
      },
      remotePayload: {
        'id': note.id,
        'title': 'Remote $suffix',
        'content': 'Remote content $suffix',
        'version': remoteVersion,
        'updated_at': '2026-11-06T10:01:00.000Z',
        'is_deleted': false,
      },
    );
  }

  test('persists KEEP_LOCAL as one rebased pending operation', () async {
    final conflict = await createResolutionFixture(suffix: 'keep-local');

    final result = await database.resolveConflict(
      conflictId: conflict.conflictId,
      strategy: ConflictResolutionStrategy.keepLocal,
    );

    expect(result.conflict.resolutionStrategy,
        ConflictResolutionStrategy.keepLocal);
    expect(result.resolutionChange!.baseVersion, 2);
    expect(result.resolutionChange!.version, 3);
    expect(result.resolutionChange!.operation, 'UPDATE');
    final changes = await database.getAllChanges();
    expect(
      changes.where((change) => change.recordId == conflict.recordId).where(
        (change) => change.effectiveState == ChangeLogState.superseded,
      ),
      isNotEmpty,
    );
    expect(
      (await database.getPendingChanges())
          .where((change) => change.recordId == conflict.recordId),
      hasLength(1),
    );
  });

  test('persists KEEP_SERVER without creating an outbound operation', () async {
    final conflict = await createResolutionFixture(suffix: 'keep-server');
    final originalChanges = (await database.getAllChanges())
        .where((change) => change.recordId == conflict.recordId)
        .toList();

    final result = await database.resolveConflict(
      conflictId: conflict.conflictId,
      strategy: ConflictResolutionStrategy.keepServer,
    );

    expect(result.resolutionChange, isNull);
    expect(await database.getPendingChanges(), isNot(contains(
      predicate<ChangeLog>((change) => change.recordId == conflict.recordId),
    )));
    final note = await database.getNoteById(conflict.recordId);
    expect(note!.content, 'Remote content keep-server');
    final changes = (await database.getAllChanges())
        .where((change) => change.recordId == conflict.recordId)
        .toList();
    expect(changes.length, originalChanges.length);
    expect(changes.every((change) =>
        change.effectiveState != ChangeLogState.pending), isTrue);
  });

  test('persists MANUAL_MERGE with validated merged content', () async {
    final conflict = await createResolutionFixture(suffix: 'manual');

    final result = await database.resolveConflict(
      conflictId: conflict.conflictId,
      strategy: ConflictResolutionStrategy.manualMerge,
      mergedPayload: {
        'id': conflict.recordId,
        'title': 'Merged title',
        'content': 'Merged content',
        'is_deleted': false,
        'updated_at': '2026-11-06T10:02:00.000Z',
      },
    );

    expect(result.resolutionChange!.baseVersion, conflict.remoteVersion);
    expect(jsonDecode(result.resolutionChange!.payload)['content'],
        'Merged content');
    expect((await database.getNoteById(conflict.recordId))!.content,
        'Merged content');
  });

  test('consolidates multiple pending changes and preserves synced history',
      () async {
    final conflict = await createResolutionFixture(suffix: 'multiple');
    final note = await database.getNoteById(conflict.recordId);
    await database.updateNote(
      note!,
      title: 'Later',
      content: 'Later content',
    );

    final before = await database.getAllChanges();
    final syncedIds = before
        .where((change) => change.recordId == conflict.recordId)
        .where((change) => change.effectiveState == ChangeLogState.synced)
        .map((change) => change.id)
        .toSet();
    await database.resolveConflict(
      conflictId: conflict.conflictId,
      strategy: ConflictResolutionStrategy.keepLocal,
    );

    final after = await database.getAllChanges();
    expect(
      after.where((change) => syncedIds.contains(change.id)).every(
        (change) => change.effectiveState == ChangeLogState.synced,
      ),
      isTrue,
    );
    expect(
      after.where((change) => change.recordId == conflict.recordId).where(
        (change) => change.effectiveState == ChangeLogState.pending,
      ),
      hasLength(1),
    );
  });

  test('keeps original snapshots and rejects duplicate resolution', () async {
    final conflict = await createResolutionFixture(suffix: 'immutable');
    final originalLocal = conflict.localPayloadJson;
    final originalRemote = conflict.remotePayloadJson;
    await database.resolveConflict(
      conflictId: conflict.conflictId,
      strategy: ConflictResolutionStrategy.keepServer,
    );

    final stored = await database.getConflictById(conflict.conflictId);
    expect(stored!.localPayloadJson, originalLocal);
    expect(stored.remotePayloadJson, originalRemote);
    expect(
      () => database.resolveConflict(
        conflictId: conflict.conflictId,
        strategy: ConflictResolutionStrategy.keepLocal,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('invalid manual payload rolls back the resolution transaction', () async {
    final conflict = await createResolutionFixture(suffix: 'rollback');
    final beforeNote = await database.getNoteById(conflict.recordId);
    final beforeChanges = (await database.getAllChanges())
        .where((change) => change.recordId == conflict.recordId)
        .toList();

    await expectLater(
      database.resolveConflict(
        conflictId: conflict.conflictId,
        strategy: ConflictResolutionStrategy.manualMerge,
        mergedPayload: {
          'id': conflict.recordId,
          'title': 'Missing content',
        },
      ),
      throwsA(isA<FormatException>()),
    );

    expect((await database.getNoteById(conflict.recordId))!.content,
        beforeNote!.content);
    expect(
      (await database.getAllChanges())
          .where((change) => change.recordId == conflict.recordId)
          .map((change) => change.effectiveState)
          .toList(),
      beforeChanges.map((change) => change.effectiveState).toList(),
    );
    expect(
      (await database.getConflictById(conflict.conflictId))!.resolutionStatus,
      ResolutionStatus.unresolved,
    );
  });
}
