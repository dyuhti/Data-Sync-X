import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:datasyncx/database/local_db.dart';
import 'package:datasyncx/main.dart';
import 'package:datasyncx/providers/note_provider.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late LocalDatabase database;
  late String databasePath;

  setUp(() async {
    databasePath = join(
      await getDatabasesPath(),
      'widget-test-${DateTime.now().microsecondsSinceEpoch}.db',
    );
    database = LocalDatabase.forTesting(databasePath);
    await database.initialize();
  });

  tearDown(() async {
    await database.close();
    await deleteDatabase(databasePath);
  });

  testWidgets('shows dashboard and switches navigation tabs', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => NoteProvider(database: database),
        child: const DataSyncXApp(),
      ),
    );

    expect(find.text('Data Sync X'), findsOneWidget);

    await tester.tap(find.text('Sync'));
    await tester.pumpAndSettle();
    expect(find.text('Synchronization'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Automatic synchronization'), findsOneWidget);
  });

  testWidgets('can create a note with validation', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => NoteProvider(database: database),
        child: const DataSyncXApp(),
      ),
    );
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('New note'), findsOneWidget);
    await tester.tap(find.text('Save note'));
    await tester.pump();
    expect(find.text('This field is required'), findsNWidgets(2));
  });
}
