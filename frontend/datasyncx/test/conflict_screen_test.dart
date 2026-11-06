import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:datasyncx/database/local_db.dart';
import 'package:datasyncx/models/conflict.dart';
import 'package:datasyncx/providers/note_provider.dart';
import 'package:datasyncx/screens/conflict_screen.dart';

class RecordingNoteProvider extends NoteProvider {
  RecordingNoteProvider({required this.conflict, required LocalDatabase database})
    : super(database: database, initialConflicts: [conflict]);

  final Conflict conflict;
  String? strategy;
  Map<String, dynamic>? mergedPayload;
  bool fail = false;

  ConflictResolutionResult _result() {
    if (fail) throw StateError('resolution failed');
    return ConflictResolutionResult(conflict: conflict);
  }

  @override
  Future<ConflictResolutionResult> keepLocal(String conflictId) {
    strategy = 'KEEP_LOCAL';
    return Future.value(_result());
  }

  @override
  Future<ConflictResolutionResult> keepServer(String conflictId) {
    strategy = 'KEEP_SERVER';
    return Future.value(_result());
  }

  @override
  Future<ConflictResolutionResult> manualMerge(
    String conflictId,
    Map<String, dynamic> payload,
  ) {
    strategy = 'MANUAL_MERGE';
    mergedPayload = payload;
    return Future.value(_result());
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
    await tester.pump();
    await tester.pump();

    expect(find.text('Selected note'), findsOneWidget);
    await tester.tap(find.text('Selected note'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Local snapshot'), findsOneWidget);
    expect(find.text('Remote snapshot'), findsOneWidget);
    expect(find.byType(Scaffold), findsNWidgets(2));
  });

  testWidgets('shows all resolution actions and confirms KEEP_LOCAL', (
    tester,
  ) async {
    final conflict = Conflict(
      conflictId: 'keep-local-ui',
      recordId: 'keep-local-record',
      conflictType: ConflictType.updateUpdate,
      operation: 'UPDATE',
      localVersion: 2,
      remoteVersion: 2,
      localPayload: {'title': 'Action note', 'content': 'Local content'},
      remotePayload: {'title': 'Action note', 'content': 'Remote content'},
      detectedAt: DateTime(2026, 11, 6, 10, 30),
    );
    final provider = RecordingNoteProvider(
      conflict: conflict,
      database: database,
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(home: ConflictScreen(conflict: conflict)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('keep-local-button')),
      300,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('keep-server-button')),
      300,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('manual-merge-button')),
      300,
    );
    expect(find.text('Keep local'), findsOneWidget);
    expect(find.text('Keep server'), findsOneWidget);
    expect(find.text('Manual merge'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('keep-local-button')),
      300,
    );
    await tester.tap(find.byKey(const ValueKey('keep-local-button')));
    await tester.pumpAndSettle();
    expect(find.text('Keep local version?'), findsOneWidget);
    expect(find.textContaining('replace the remote version'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('confirms KEEP_SERVER and refreshes the conflict list', (
    tester,
  ) async {
    final conflict = Conflict(
      conflictId: 'keep-server-ui',
      recordId: 'keep-server-record',
      conflictType: ConflictType.updateUpdate,
      operation: 'UPDATE',
      localVersion: 2,
      remoteVersion: 2,
      localPayload: {'title': 'Action note', 'content': 'Local content'},
      remotePayload: {'title': 'Action note', 'content': 'Remote content'},
      detectedAt: DateTime(2026, 11, 6, 10, 30),
    );
    final provider = RecordingNoteProvider(
      conflict: conflict,
      database: database,
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(home: ConflictScreen(conflict: conflict)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('keep-server-button')),
      300,
    );
    await tester.tap(find.byKey(const ValueKey('keep-server-button')));
    await tester.pumpAndSettle();
    expect(find.text('Keep server version?'), findsOneWidget);
    expect(find.textContaining('superseded'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('validates the manual merge editor before saving', (
    tester,
  ) async {
    final conflict = Conflict(
      conflictId: 'merge-validation',
      recordId: 'merge-record',
      conflictType: ConflictType.updateUpdate,
      operation: 'UPDATE',
      localVersion: 2,
      remoteVersion: 2,
      localPayload: {'title': 'Local', 'content': 'Local content'},
      remotePayload: {'title': 'Remote', 'content': 'Remote content'},
      detectedAt: DateTime(2026, 11, 6, 10, 30),
    );
    await tester.pumpWidget(
      MaterialApp(home: ConflictScreen(conflict: conflict)),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('manual-merge-button')),
      300,
    );
    await tester.tap(find.byKey(const ValueKey('manual-merge-button')));
    await tester.pumpAndSettle();

    expect(find.text('Create merged version'), findsOneWidget);
    expect(find.byKey(const ValueKey('save-merged-button')), findsOneWidget);
    expect(find.text('Local content'), findsNWidgets(2));
    expect(find.text('Remote content'), findsOneWidget);
  });

  testWidgets('retains a conflict after a failed resolution', (tester) async {
    final conflict = Conflict(
      conflictId: 'missing-conflict',
      recordId: 'missing-record',
      conflictType: ConflictType.updateUpdate,
      operation: 'UPDATE',
      localVersion: 2,
      remoteVersion: 2,
      localPayload: {'title': 'Missing', 'content': 'Local'},
      remotePayload: {'title': 'Missing', 'content': 'Remote'},
      detectedAt: DateTime(2026, 11, 6, 10, 30),
    );
    final provider = RecordingNoteProvider(
      conflict: conflict,
      database: database,
    )..fail = true;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(home: ConflictScreen(conflict: conflict)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('keep-local-button')),
      300,
    );
    await tester.tap(find.byKey(const ValueKey('keep-local-button')));
    await tester.pump();
    expect(find.byKey(const ValueKey('keep-local-button')), findsOneWidget);
    expect(provider.unresolvedConflicts, hasLength(1));
  });

  testWidgets('shows deleted remote snapshots', (tester) async {
    final conflict = Conflict(
      conflictId: 'deleted-remote-ui',
      recordId: 'deleted-remote-record',
      conflictType: ConflictType.updateDelete,
      operation: 'UPDATE',
      localVersion: 1,
      remoteVersion: 1,
      localPayload: {
        'title': 'Deleted note',
        'content': 'Local content',
        'is_deleted': false,
      },
      remotePayload: {
        'title': 'Deleted note',
        'content': 'Remote deleted content',
        'is_deleted': true,
      },
      detectedAt: DateTime(2026, 11, 6, 10, 30),
    );
    await tester.pumpWidget(
      MaterialApp(home: ConflictScreen(conflict: conflict)),
    );

    expect(find.text('Deleted'), findsOneWidget);
    expect(find.text('Remote deleted content'), findsOneWidget);
  });
}
