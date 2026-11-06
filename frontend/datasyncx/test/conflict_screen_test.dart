import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:datasyncx/database/local_db.dart';
import 'package:datasyncx/models/conflict.dart';
import 'package:datasyncx/providers/note_provider.dart';
import 'package:datasyncx/screens/conflict_screen.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late LocalDatabase database;
  late String databasePath;

  setUp(() async {
    databasePath = join(
      await getDatabasesPath(),
      'conflict-screen-test-${DateTime.now().microsecondsSinceEpoch}.db',
    );
    database = LocalDatabase.forTesting(databasePath);
    await database.initialize();
  });

  tearDown(() async {
    await database.close();
    await deleteDatabase(databasePath);
  });

  testWidgets('shows an empty state when there are no unresolved conflicts', (
    tester,
  ) async {
    final provider = NoteProvider(database: database);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: ConflictScreen()),
      ),
    );

    expect(find.text('No unresolved conflicts'), findsOneWidget);
  });

  testWidgets('displays stored local and remote snapshots', (tester) async {
    final conflict = Conflict(
      conflictId: 'detail-${DateTime.now().microsecondsSinceEpoch}',
      recordId: 'detail-record',
      conflictType: ConflictType.updateDelete,
      operation: 'UPDATE',
      localVersion: 2,
      remoteVersion: 3,
      localPayload: {'title': 'Planning', 'content': 'Local meeting plan'},
      remotePayload: {
        'title': 'Planning',
        'content': 'Remote deleted snapshot',
        'is_deleted': true,
      },
      detectedAt: DateTime(2026, 11, 6, 10, 30),
    );

    await tester.pumpWidget(
      MaterialApp(home: ConflictScreen(conflict: conflict)),
    );

    expect(find.text('Planning'), findsOneWidget);
    expect(find.text('UPDATE_DELETE'), findsOneWidget);
    expect(find.text('Local meeting plan'), findsOneWidget);
    expect(find.text('Remote deleted snapshot'), findsOneWidget);
    expect(find.text('Version 2'), findsOneWidget);
    expect(find.text('Version 3'), findsOneWidget);
    expect(find.text('unresolved'), findsOneWidget);
    expect(find.text('Last-Writer-Wins'), findsNothing);
    expect(find.text('Field-Level Merge'), findsNothing);
    expect(find.text('Manual Review'), findsNothing);
    expect(find.text('Keep my version'), findsNothing);
    expect(find.text('Keep server version'), findsNothing);
  });

  testWidgets('loads unresolved conflicts and opens selected details', (
    tester,
  ) async {
    final provider = NoteProvider(
      database: database,
      initialConflicts: [
        Conflict(
          conflictId: 'ui-conflict',
          recordId: 'ui-record',
          conflictType: ConflictType.updateUpdate,
          operation: 'UPDATE',
          localVersion: 2,
          remoteVersion: 2,
          localPayload: {'title': 'Selected note', 'content': 'Local snapshot'},
          remotePayload: {
            'title': 'Selected note',
            'content': 'Remote snapshot',
          },
          detectedAt: DateTime(2026, 11, 6, 10, 30),
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: ConflictScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Selected note'), findsOneWidget);
    await tester.tap(find.text('Selected note'));
    await tester.pumpAndSettle();

    expect(find.text('Local snapshot'), findsOneWidget);
    expect(find.text('Remote snapshot'), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
