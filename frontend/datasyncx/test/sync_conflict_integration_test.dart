import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'package:datasyncx/database/local_db.dart';
import 'package:datasyncx/models/conflict.dart';
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
}
