import 'package:flutter/foundation.dart';

import '../models/note.dart';

class NoteProvider extends ChangeNotifier {
  NoteProvider()
      : _notes = [
          Note(
            id: '1',
            title: 'Project kickoff notes',
            content: 'Outline the first sprint goals and align with the team.',
            updatedAt: DateTime.now().subtract(const Duration(minutes: 18)),
            syncStatus: NoteSyncStatus.synced,
          ),
          Note(
            id: '2',
            title: 'Ideas for weekend',
            content: 'Try the new coffee shop and take a long walk by the lake.',
            updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
            syncStatus: NoteSyncStatus.pending,
          ),
          Note(
            id: '3',
            title: 'Reading list',
            content: 'Add books about design systems, productivity, and mindfulness.',
            updatedAt: DateTime.now().subtract(const Duration(days: 1)),
            syncStatus: NoteSyncStatus.synced,
          ),
        ];

  final List<Note> _notes;

  List<Note> get notes => List.unmodifiable(_notes);
  int get pendingCount =>
      _notes.where((note) => note.syncStatus == NoteSyncStatus.pending).length;

  void addNote(String title, String content) {
    _notes.insert(
      0,
      Note(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        content: content,
        updatedAt: DateTime.now(),
        syncStatus: NoteSyncStatus.pending,
      ),
    );
    notifyListeners();
  }

  void updateNote(Note note, String title, String content) {
    note
      ..title = title
      ..content = content
      ..updatedAt = DateTime.now()
      ..syncStatus = NoteSyncStatus.pending;
    notifyListeners();
  }

  void deleteNote(Note note) {
    _notes.removeWhere((item) => item.id == note.id);
    notifyListeners();
  }
}
