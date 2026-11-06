import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:datasyncx/main.dart';
import 'package:datasyncx/providers/note_provider.dart';

void main() {
  testWidgets('shows dashboard and switches navigation tabs', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => NoteProvider(),
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
        create: (_) => NoteProvider(),
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
