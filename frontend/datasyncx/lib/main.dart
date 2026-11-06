import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'database/local_db.dart';
import 'providers/note_provider.dart';
import 'screens/conflict_screen.dart';
import 'screens/home_screen.dart';
import 'screens/note_editor_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sync_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final noteProvider = NoteProvider(database: LocalDatabase.instance);
  try {
    await noteProvider.loadNotes();
  } on Object {
    // The provider exposes the error and the app remains usable for retry.
  }
  runApp(
    ChangeNotifierProvider(
      create: (_) => noteProvider,
      child: const DataSyncXApp(),
    ),
  );
}

class DataSyncXApp extends StatelessWidget {
  const DataSyncXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Data Sync X',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  static const _pages = <Widget>[
    HomeScreen(),
    SyncScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const NoteEditorScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('Add note'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.sync_outlined),
            selectedIcon: Icon(Icons.sync),
            label: 'Sync',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class ConflictRoute extends MaterialPageRoute<void> {
  ConflictRoute()
      : super(builder: (_) => const ConflictScreen());
}
