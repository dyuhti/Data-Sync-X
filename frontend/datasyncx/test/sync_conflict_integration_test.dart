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

  Map<String, dynamic> notesResponse([
    List<Map<String, dynamic>> notes = const [],
  ]) => {'status': 'ok', 'notes': notes};

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
        if (request.method == 'GET') {
          return http.Response(jsonEncode(notesResponse()), 200);
        }
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

  test('recreates a missing remote note when an UPDATE returns 404', () async {
    final note = await database.insertNote(
      title: 'Local note',
      content: 'Original content',
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
        'title': 'Updated note',
        'content': 'Updated content',
        'version': 2,
        'updated_at': '2026-11-06T10:00:00.000Z',
        'is_deleted': false,
      }),
    );
    Map<String, dynamic>? recreatedNote;
    final client = RecordingClient((request) async {
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode(
            notesResponse(recreatedNote == null ? [] : [recreatedNote!]),
          ),
          200,
        );
      }
      if (request.method == 'PUT') {
        return http.Response(
          jsonEncode({'status': 'error', 'message': 'Note not found.'}),
          404,
        );
      }
      expect(request.method, 'POST');
      recreatedNote =
          jsonDecode((request as http.Request).body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({'status': 'ok', 'note': recreatedNote}),
        201,
      );
    });

    final result = await SyncService(
      database: database,
      client: client,
      baseUrl: 'http://test',
    ).syncPendingChanges();

    expect(result.succeeded, isTrue);
    expect(recreatedNote?['title'], 'Updated note');
    expect(recreatedNote?['version'], 2);
    expect(
      (await database.getAllChanges())
          .firstWhere((item) => item.id == change.id)
          .synced,
      isTrue,
    );
    expect(client.requests.map((request) => request.method), [
      'GET',
      'PUT',
      'POST',
      'GET',
    ]);
  });

  test(
    'records a conflict if a different note exists during recovery',
    () async {
      final note = await database.insertNote(
        title: 'Local note',
        content: 'Original content',
      );
      final create = (await database.getPendingChanges()).single;
      await database.markChangesAsSynced([create.id]);
      await database.insertChangeLog(
        recordId: note.id,
        operation: 'UPDATE',
        baseVersion: 1,
        version: 2,
        payload: jsonEncode({
          'id': note.id,
          'title': 'Updated note',
          'content': 'Updated content',
          'version': 2,
          'updated_at': '2026-11-06T10:00:00.000Z',
          'is_deleted': false,
        }),
      );
      final remote = {
        'id': note.id,
        'title': 'Different server note',
        'content': 'Server content',
        'version': 1,
        'updated_at': '2026-11-06T09:00:00.000Z',
        'is_deleted': false,
      };
      final client = RecordingClient((request) async {
        if (request.method == 'GET') {
          return http.Response(jsonEncode(notesResponse()), 200);
        }
        if (request.method == 'PUT') {
          return http.Response(
            jsonEncode({'status': 'error', 'message': 'Note not found.'}),
            404,
          );
        }
        expect(request.method, 'POST');
        return http.Response(
          jsonEncode({
            'status': 'conflict',
            'conflict_type': 'DUPLICATE_INSERT',
            'record_id': note.id,
            'local_version': 2,
            'remote_version': 1,
            'local_payload': {'id': note.id, 'version': 2},
            'remote_payload': remote,
            'operation': 'CREATE',
          }),
          409,
        );
      });

      final result = await SyncService(
        database: database,
        client: client,
        baseUrl: 'http://test',
      ).syncPendingChanges();
      final conflicts = await database.getUnresolvedConflicts();

      expect(result.succeeded, isFalse);
      expect(conflicts, hasLength(1));
      expect(conflicts.single.conflictType, ConflictType.updateUpdate);
      expect(conflicts.single.operation, 'UPDATE');
      expect(await database.getPendingChangesCount(), 1);
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
      if (request.method == 'GET') {
        return http.Response(jsonEncode(notesResponse()), 200);
      }
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

  test('downloads remote notes without creating local changes', () async {
    final remote = {
      'id': 'remote-note',
      'title': 'Shared note',
      'content': 'Created on another device',
      'version': 1,
      'updated_at': '2026-11-06T10:00:00.000Z',
      'is_deleted': false,
    };
    final client = RecordingClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/notes');
      return http.Response(jsonEncode(notesResponse([remote])), 200);
    });

    final result = await SyncService(
      database: database,
      client: client,
      baseUrl: 'http://test',
    ).syncPendingChanges();
    final note = await database.getNoteById('remote-note');

    expect(result.succeeded, isTrue);
    expect(result.downloadedNotes, 1);
    expect(note?.title, 'Shared note');
    expect(note?.content, 'Created on another device');
    expect(note?.syncStatus, NoteSyncStatus.synced);
    expect(await database.getPendingChangesCount(), 0);
  });

  test('pulls a newer remote version over a synced local note', () async {
    final note = await database.insertNote(
      title: 'Original note',
      content: 'Original content',
    );
    final create = (await database.getPendingChanges()).single;
    await database.markChangesAsSynced([create.id]);

    final changedNotes = await database.mergeRemoteNotes([
      {
        'id': note.id,
        'title': 'Remote update',
        'content': 'Updated from another device',
        'version': 2,
        'updated_at': '2026-11-06T10:01:00.000Z',
        'is_deleted': false,
      },
    ]);

    final storedNote = await database.getNoteById(note.id);
    expect(changedNotes, 1);
    expect(storedNote?.title, 'Remote update');
    expect(storedNote?.content, 'Updated from another device');
    expect(storedNote?.version, 2);
    expect(storedNote?.syncStatus, NoteSyncStatus.synced);
    expect(await database.getPendingChangesCount(), 0);
  });

  test('pulls remote soft deletions without adding local changes', () async {
    final note = await database.insertNote(
      title: 'Deleted remotely',
      content: 'Original content',
    );
    final create = (await database.getPendingChanges()).single;
    await database.markChangesAsSynced([create.id]);

    final changedNotes = await database.mergeRemoteNotes([
      {
        'id': note.id,
        'title': note.title,
        'content': note.content,
        'version': 2,
        'updated_at': '2026-11-06T10:01:00.000Z',
        'is_deleted': true,
      },
    ]);
    final rows = await (await database.database).query(
      'notes',
      where: 'id = ?',
      whereArgs: [note.id],
    );

    expect(changedNotes, 1);
    expect(rows.single['is_deleted'], 1);
    expect(await database.getNoteById(note.id), isNull);
    expect(await database.getPendingChangesCount(), 0);
  });

  test(
    'repeated pulls do not duplicate records or change-log entries',
    () async {
      final remote = {
        'id': 'remote-note',
        'title': 'Shared note',
        'content': 'Created on another device',
        'version': 1,
        'updated_at': '2026-11-06T10:00:00.000Z',
        'is_deleted': false,
      };

      expect(await database.mergeRemoteNotes([remote]), 1);
      expect(await database.mergeRemoteNotes([remote]), 0);
      expect(
        (await database.getAllNotes()).where((n) => n.id == remote['id']),
        hasLength(1),
      );
      expect(await database.getAllChanges(), isEmpty);
    },
  );

  test(
    'retains offline uploads and retries successfully when online',
    () async {
      var online = false;
      final remoteNotes = <Map<String, dynamic>>[];
      final client = RecordingClient((request) async {
        if (!online) {
          return http.Response('unavailable', 503);
        }
        if (request.method == 'GET') {
          return http.Response(jsonEncode(notesResponse(remoteNotes)), 200);
        }
        expect(request.method, 'POST');
        final created =
            jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        remoteNotes.add(created);
        return http.Response(
          jsonEncode({'status': 'ok', 'note': created}),
          201,
        );
      });
      final service = SyncService(
        database: database,
        client: client,
        baseUrl: 'http://test',
      );
      await database.insertNote(title: 'Offline note', content: 'Retry me');

      final offlineResult = await service.syncPendingChanges();
      expect(offlineResult.succeeded, isFalse);
      expect(offlineResult.remainingPending, 1);
      expect(client.requests, hasLength(1));

      online = true;
      final retryResult = await service.syncPendingChanges();

      expect(retryResult.succeeded, isTrue);
      expect(retryResult.remainingPending, 0);
      expect(remoteNotes, hasLength(1));
      expect(
        (await database.getAllChanges()).single.effectiveState,
        ChangeLogState.synced,
      );
    },
  );

  test('does not replace a note with pending local changes', () async {
    final note = await database.insertNote(
      title: 'Local note',
      content: 'Local content',
    );
    await database.updateNote(
      note,
      title: 'Edited locally',
      content: 'Local edit',
    );

    final changedNotes = await database.mergeRemoteNotes([
      {
        'id': note.id,
        'title': 'Remote note',
        'content': 'Remote edit',
        'version': 10,
        'updated_at': '2026-11-06T10:00:00.000Z',
        'is_deleted': false,
      },
    ]);

    final storedNote = await database.getNoteById(note.id);
    expect(changedNotes, 0);
    expect(storedNote?.title, 'Edited locally');
    expect(storedNote?.content, 'Local edit');
    expect(await database.getPendingChangesCount(), 2);
  });

  test(
    'two devices editing before sync creates an unresolved conflict',
    () async {
      final remoteNotes = <String, Map<String, dynamic>>{};
      Future<http.Response> handleRequest(http.BaseRequest request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode(notesResponse(remoteNotes.values.toList())),
            200,
          );
        }

        final body =
            jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        if (request.method == 'POST') {
          final note = Map<String, dynamic>.from(body);
          remoteNotes[note['id'] as String] = note;
          return http.Response(jsonEncode({'status': 'ok', 'note': note}), 201);
        }

        expect(request.method, 'PUT');
        final id = request.url.pathSegments.last;
        final remote = remoteNotes[id]!;
        final baseVersion = body['base_version'] as int;
        if (baseVersion != remote['version']) {
          return http.Response(
            jsonEncode({
              'status': 'conflict',
              'conflict_type': 'UPDATE_UPDATE',
              'record_id': id,
              'local_version': body['version'],
              'remote_version': remote['version'],
              'local_payload': body,
              'remote_payload': remote,
              'operation': 'UPDATE',
            }),
            409,
          );
        }
        final updated = {
          ...remote,
          'title': body['title'],
          'content': body['content'],
          'version': baseVersion + 1,
          'updated_at': '2026-11-06T10:01:00.000Z',
        };
        remoteNotes[id] = updated;
        return http.Response(
          jsonEncode({'status': 'ok', 'note': updated}),
          200,
        );
      }

      final secondDatabasePath = join(
        await getDatabasesPath(),
        'sync-test-${const Uuid().v4()}.db',
      );
      final secondDatabase = LocalDatabase.forTesting(secondDatabasePath);
      await secondDatabase.initialize();

      try {
        final firstService = SyncService(
          database: database,
          client: RecordingClient(handleRequest),
          baseUrl: 'http://test',
        );
        final secondService = SyncService(
          database: secondDatabase,
          client: RecordingClient(handleRequest),
          baseUrl: 'http://test',
        );

        final firstNote = await database.insertNote(
          title: 'Conflict demo',
          content: 'Original content',
        );
        expect((await firstService.syncPendingChanges()).succeeded, isTrue);
        expect((await secondService.syncPendingChanges()).downloadedNotes, 1);

        await database.updateNote(
          firstNote,
          title: 'Edited on A',
          content: 'Change from emulator A',
        );
        final secondNote = (await secondDatabase.getNoteById(firstNote.id))!;
        await secondDatabase.updateNote(
          secondNote,
          title: 'Edited on B',
          content: 'Change from emulator B',
        );

        final secondResult = await secondService.syncPendingChanges();
        expect(secondResult.succeeded, isTrue);
        final firstResult = await firstService.syncPendingChanges();
        final conflicts = await database.getUnresolvedConflicts();

        expect(firstResult.failedOperations, 1);
        expect(conflicts, hasLength(1));
        expect(conflicts.single.recordId, firstNote.id);
        expect(
          conflicts.single.localPayload['content'],
          'Change from emulator A',
        );
        expect(
          conflicts.single.remotePayload['content'],
          'Change from emulator B',
        );
      } finally {
        await secondDatabase.close();
        await deleteDatabase(secondDatabasePath);
      }
    },
  );

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
        if (request.method == 'GET') {
          return http.Response(jsonEncode(notesResponse()), 200);
        }
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
      expect(requestCount, 3);
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
      expect(requestCount, 5);
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

  test('provider refreshes when sync detects a remote conflict', () async {
    final note = await database.insertNote(
      title: 'Provider conflict',
      content: 'Original content',
    );
    final create = (await database.getPendingChanges()).single;
    await database.markChangesAsSynced([create.id]);
    await database.updateNote(
      note,
      title: 'Local edit',
      content: 'Local content',
    );
    final service = SyncService(
      database: database,
      client: RecordingClient((request) async {
        if (request.method == 'GET') {
          return http.Response(jsonEncode(notesResponse()), 200);
        }
        return http.Response(
          jsonEncode(conflictResponse(note.id, 'UPDATE')),
          409,
        );
      }),
      baseUrl: 'http://test',
    );
    final provider = NoteProvider(database: database, syncService: service);

    await provider.syncPendingChanges();

    expect(provider.unresolvedConflictCount, 1);
    expect(provider.unresolvedConflicts.single.recordId, note.id);
    expect(provider.failedSyncCount, 1);
    expect(provider.pendingChangesCount, 1);
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
        if (request.method == 'GET') {
          return http.Response(jsonEncode(notesResponse()), 200);
        }
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
        if (request.method == 'GET') {
          return http.Response(jsonEncode(notesResponse()), 200);
        }
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
        if (request.method == 'GET') {
          return http.Response(jsonEncode(notesResponse()), 200);
        }
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
