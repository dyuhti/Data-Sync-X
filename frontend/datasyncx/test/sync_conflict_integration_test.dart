import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'package:datasyncx/database/local_db.dart';
import 'package:datasyncx/models/change_log.dart';
import 'package:datasyncx/models/conflict.dart';
import 'package:datasyncx/models/note.dart';
import 'package:datasyncx/providers/note_provider.dart';
import 'package:datasyncx/services/sync_service.dart';

class RecordingClient extends http.BaseClient {
  RecordingClient(this.handler);

  final Future<http.Response> Function(http.BaseRequest request) handler;
  final List<http.BaseRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final response = await handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: request,
    );
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late LocalDatabase database;
  late String databasePath;

  setUp(() async {
    databasePath = join(
      await getDatabasesPath(),
      'sync-test-${const Uuid().v4()}.db',
    );
    database = LocalDatabase.forTesting(databasePath);
    await database.initialize();
  });

  tearDown(() async {
    await database.close();
    await deleteDatabase(databasePath);
  });

  Map<String, dynamic> noteResponse(
    String id, {
    int version = 2,
    bool isDeleted = false,
  }) => {
    'status': 'ok',
    'note': {
      'id': id,
      'title': 'Remote note',
      'content': 'Remote content',
      'version': version,
      'updated_at': '2026-11-06T10:00:00.000Z',
      'is_deleted': isDeleted,
    },
  };

  Map<String, dynamic> conflictResponse(String id, String operation) => {
    'status': 'conflict',
    'conflict_type': 'UPDATE_UPDATE',
    'record_id': id,
    'local_version': 2,
    'remote_version': 2,
    'local_payload': {'id': id, 'content': 'Local content', 'version': 2},
    'remote_payload': {'id': id, 'content': 'Remote content', 'version': 2},
    'operation': operation,
  };

  Future<Conflict> createResolvedConflictFixture({
    required String suffix,
    required ConflictType type,
  }) async {
    final note = await database.insertNote(
      title: 'Local $suffix',
      content: 'Local content $suffix',
    );
    final create = (await database.getPendingChanges()).lastWhere(
      (change) => change.recordId == note.id,
    );
    await database.markChangesAsSynced([create.id]);
    final change = await database.insertChangeLog(
      recordId: note.id,
      operation: 'UPDATE',
      baseVersion: 1,
      version: 2,
      payload: jsonEncode({
        'id': note.id,
        'title': 'Local $suffix',
        'content': 'Local content $suffix',
        'version': 2,
        'updated_at': '2026-11-06T10:00:00.000Z',
        'is_deleted': false,
      }),
    );
    return database.insertConflict(
      recordId: note.id,
      conflictType: type,
      operation: change.operation,
      localVersion: 2,
      remoteVersion: 2,
      localPayload: jsonDecode(change.payload) as Map<String, dynamic>,
      remotePayload: {
        'id': note.id,
        'title': 'Remote $suffix',
        'content': 'Remote content $suffix',
        'version': 2,
        'updated_at': '2026-11-06T10:01:00.000Z',
        'is_deleted': false,
      },
    );
  }

  test(
    'sends base_version with UPDATE and successful sync marks it synced',
    () async {
      late String recordId;
      final client = RecordingClient((request) async {
        final body = jsonDecode((request as http.Request).body);
        recordId = request.url.pathSegments.last;
        expect(request.method, 'PUT');
        expect(body['base_version'], 1);
        return http.Response(jsonEncode(noteResponse(recordId)), 200);
      });
      final service = SyncService(
        database: database,
        client: client,
        baseUrl: 'http://test',
      );
      final note = await database.insertNote(
        title: 'Local note',
        content: 'Local content',
      );
      final create = (await database.getPendingChanges()).single;
      await database.markChangesAsSynced([create.id]);
      final change = await database.insertChangeLog(
        recordId: note.id,
        operation: 'UPDATE',
        baseVersion: 1,
        version: 2,
        payload: jsonEncode({
          'id': note.id,
          'title': 'Local note',
          'content': 'Local content',
          'version': 2,
        }),
      );

      final result = await service.syncPendingChanges();

      expect(result.succeeded, isTrue);
      expect(
        (await database.getAllChanges())
            .firstWhere((c) => c.id == change.id)
            .synced,
        isTrue,
      );
    },
  );

  test('sends base_version with DELETE', () async {
    final note = await database.insertNote(
      title: 'Delete note',
      content: 'Delete content',
    );
    final create = (await database.getPendingChanges()).lastWhere(
      (change) => change.recordId == note.id,
    );
    await database.markChangesAsSynced([create.id]);
    final change = await database.insertChangeLog(
      recordId: note.id,
      operation: 'DELETE',
      baseVersion: 1,
      version: 2,
      payload: jsonEncode({'id': note.id, 'version': 2, 'is_deleted': true}),
    );
    final client = RecordingClient((request) async {
      expect(request.method, 'DELETE');
      expect(
        jsonDecode((request as http.Request).body)['base_version'],
        change.baseVersion,
      );
      return http.Response(
        jsonEncode(noteResponse(note.id, isDeleted: true)),
        200,
      );
    });

    final result = await SyncService(
      database: database,
      client: client,
      baseUrl: 'http://test',
    ).syncPendingChanges();

    expect(result.succeeded, isTrue);
    expect(
      (await database.getAllChanges())
          .firstWhere((c) => c.id == change.id)
          .synced,
      isTrue,
    );
  });

  test(
    'stores structured 409, keeps change pending, and blocks later changes',
    () async {
      final note = await database.insertNote(
        title: 'Conflict note',
        content: 'Local content',
      );
      final create = (await database.getPendingChanges()).lastWhere(
        (change) => change.recordId == note.id,
      );
      await database.markChangesAsSynced([create.id]);
      final first = await database.insertChangeLog(
        recordId: note.id,
        operation: 'UPDATE',
        baseVersion: 1,
        version: 2,
        payload: jsonEncode({'id': note.id, 'content': 'Local content'}),
      );
      final later = await database.insertChangeLog(
        recordId: note.id,
        operation: 'UPDATE',
        baseVersion: 2,
        version: 3,
        payload: jsonEncode({'id': note.id, 'content': 'Later content'}),
      );
      var requestCount = 0;
      final client = RecordingClient((request) async {
        requestCount++;
        return http.Response(
          jsonEncode(conflictResponse(note.id, 'UPDATE')),
          409,
        );
      });
      final service = SyncService(
        database: database,
        client: client,
        baseUrl: 'http://test',
      );

      final result = await service.syncPendingChanges();
      final conflicts = await database.getConflictsForRecord(note.id);

      expect(result.failedOperations, 1);
      expect(result.remainingPending, 2);
      expect(requestCount, 1);
      expect(
        (await database.getAllChanges())
            .firstWhere((c) => c.id == first.id)
            .synced,
        isFalse,
      );
      expect(
        (await database.getAllChanges())
            .firstWhere((c) => c.id == later.id)
            .synced,
        isFalse,
      );
      expect(conflicts.single.localPayload['content'], 'Local content');
      expect(conflicts.single.remotePayload['content'], 'Remote content');

      await service.syncPendingChanges();
      expect(await database.getConflictsForRecord(note.id), hasLength(1));
    },
  );

  test('provider exposes unresolved conflicts', () async {
    final recordId = 'provider-${DateTime.now().microsecondsSinceEpoch}';
    await database.insertConflict(
      recordId: recordId,
      conflictType: ConflictType.updateDelete,
      operation: 'UPDATE',
      localVersion: 2,
      remoteVersion: 2,
      localPayload: {'content': 'local'},
      remotePayload: {'content': 'remote', 'is_deleted': true},
    );
    final provider = NoteProvider(database: database);

    await provider.loadConflicts();

    expect(provider.unresolvedConflicts, isNotEmpty);
    expect(provider.unresolvedConflictCount, greaterThan(0));
  });

  test(
    'KEEP_LOCAL syncs only the consolidated operation at remote version',
    () async {
      final conflict = await createResolvedConflictFixture(
        suffix: 'keep-local-sync',
        type: ConflictType.updateUpdate,
      );
      final resolution = await database.resolveConflict(
        conflictId: conflict.conflictId,
        strategy: ConflictResolutionStrategy.keepLocal,
      );
      final requests = <http.BaseRequest>[];
      final client = RecordingClient((request) async {
        requests.add(request);
        expect(request.method, 'PUT');
        final body = jsonDecode((request as http.Request).body);
        expect(body['base_version'], 2);
        expect(body['content'], 'Local content keep-local-sync');
        return http.Response(
          jsonEncode(noteResponse(conflict.recordId, version: 3)),
          200,
        );
      });

      final result = await SyncService(
        database: database,
        client: client,
        baseUrl: 'http://test',
      ).syncPendingChanges();

      expect(result.succeeded, isTrue);
      expect(requests, hasLength(1));
      expect(
        resolution.resolutionChange!.effectiveState,
        ChangeLogState.pending,
      );
      expect(
        (await database.getAllChanges()).where(
          (change) => change.effectiveState == ChangeLogState.superseded,
        ),
        hasLength(1),
      );
      expect(
        (await database.getAllChanges())
            .firstWhere(
              (change) => change.id == resolution.resolutionChange!.id,
            )
            .effectiveState,
        ChangeLogState.synced,
      );
    },
  );

  test(
    'KEEP_SERVER creates no outbound request and leaves the note synced',
    () async {
      final conflict = await createResolvedConflictFixture(
        suffix: 'keep-server-sync',
        type: ConflictType.updateUpdate,
      );
      await database.resolveConflict(
        conflictId: conflict.conflictId,
        strategy: ConflictResolutionStrategy.keepServer,
      );
      final client = RecordingClient((request) async {
        fail('KEEP_SERVER must not send a request.');
      });

      final result = await SyncService(
        database: database,
        client: client,
        baseUrl: 'http://test',
      ).syncPendingChanges();

      expect(result.succeeded, isTrue);
      expect(result.remainingPending, 0);
      expect(
        (await database.getNoteById(conflict.recordId))!.syncStatus,
        NoteSyncStatus.synced,
      );
    },
  );

  test(
    'MANUAL_MERGE syncs merged content with the remote base version',
    () async {
      final conflict = await createResolvedConflictFixture(
        suffix: 'manual-sync',
        type: ConflictType.updateUpdate,
      );
      final resolution = await database.resolveConflict(
        conflictId: conflict.conflictId,
        strategy: ConflictResolutionStrategy.manualMerge,
        mergedPayload: {
          'id': conflict.recordId,
          'title': 'Merged title',
          'content': 'Merged content',
          'version': 3,
          'updated_at': '2026-11-06T10:02:00.000Z',
          'is_deleted': false,
        },
      );
      final client = RecordingClient((request) async {
        expect(request.method, 'PUT');
        final body = jsonDecode((request as http.Request).body);
        expect(body['base_version'], 2);
        expect(body['title'], 'Merged title');
        expect(body['content'], 'Merged content');
        return http.Response(
          jsonEncode(noteResponse(conflict.recordId, version: 3)),
          200,
        );
      });

      await SyncService(
        database: database,
        client: client,
        baseUrl: 'http://test',
      ).syncPendingChanges();

      expect(
        (await database.getAllChanges())
            .firstWhere(
              (change) => change.id == resolution.resolutionChange!.id,
            )
            .effectiveState,
        ChangeLogState.synced,
      );
    },
  );
}
