import 'package:flutter/foundation.dart';

import '../database/local_db.dart';
import '../models/change_log.dart';
import '../models/conflict.dart';
import '../models/note.dart';
import '../services/sync_service.dart';

class NoteProvider extends ChangeNotifier {
  NoteProvider({
    LocalDatabase? database,
    SyncService? syncService,
    List<Conflict>? initialConflicts,
  }) : _unresolvedConflicts = initialConflicts ?? [],
       _database = database ?? LocalDatabase.instance,
       _syncService = syncService ?? SyncService(database: database);

  final LocalDatabase _database;
  final SyncService _syncService;
  List<Note> _notes = [];
  List<ChangeLog> _changes = [];
  List<Conflict> _unresolvedConflicts;
  bool _isLoading = false;
  String? _errorMessage;
  SyncResult? _lastSyncResult;
  DateTime? _lastSyncTime;
  bool _isSyncing = false;

  List<Note> get notes => List.unmodifiable(_notes);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get pendingCount =>
      _notes.where((note) => note.syncStatus == NoteSyncStatus.pending).length;
  List<ChangeLog> get changes => List.unmodifiable(_changes);
  List<Conflict> get unresolvedConflicts =>
      List.unmodifiable(_unresolvedConflicts);
  int get unresolvedConflictCount => _unresolvedConflicts.length;
  List<ChangeLog> get pendingChanges =>
      List.unmodifiable(_changes.where((change) => !change.synced));
  int get pendingChangesCount => pendingChanges.length;
  int get createChangesCount =>
      _changes.where((change) => change.operation == 'CREATE').length;
  int get updateChangesCount =>
      _changes.where((change) => change.operation == 'UPDATE').length;
  int get deleteChangesCount =>
      _changes.where((change) => change.operation == 'DELETE').length;
  bool get isSyncing => _isSyncing;
  int get successfulOperationsCount =>
      _lastSyncResult?.successfulOperations ?? 0;
  int get failedOperationsCount => _lastSyncResult?.failedOperations ?? 0;
  int get remainingPendingCount => pendingChangesCount;
  DateTime? get lastSyncTime => _lastSyncTime;
  String? get lastSyncError => _lastSyncResult?.error;
  SyncResult? get lastSyncResult => _lastSyncResult;

  Future<void> syncPendingChanges() async {
    if (_isSyncing) return;
    _isSyncing = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _lastSyncResult = await _syncService.syncPendingChanges();
      _lastSyncTime = DateTime.now();
      _changes = await _database.getAllChanges();
      _notes = await _database.getAllNotes();
      _unresolvedConflicts = await _database.getUnresolvedConflicts();
      if (_lastSyncResult!.error != null) {
        _errorMessage = _lastSyncResult!.error;
      }
    } on Object catch (error) {
      _errorMessage = 'Synchronization failed: $error';
      rethrow;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> loadNotes() async {
    await _runDatabaseOperation(() async {
      _notes = await _database.getAllNotes();
      _changes = await _database.getAllChanges();
      _unresolvedConflicts = await _database.getUnresolvedConflicts();
    });
  }

  Future<void> refreshNotes() => loadNotes();

  Future<void> loadPendingChanges() async {
    await _runDatabaseOperation(() async {
      _changes = await _database.getPendingChanges();
    });
  }

  Future<void> loadChangeHistory() async {
    await _runDatabaseOperation(() async {
      _changes = await _database.getAllChanges();
    });
  }

  Future<void> loadConflicts() async {
    await _runDatabaseOperation(() async {
      _unresolvedConflicts = await _database.getUnresolvedConflicts();
    });
  }

  Future<void> markChangesAsSynced(Iterable<String> operationIds) async {
    await _runDatabaseOperation(() async {
      await _database.markChangesAsSynced(operationIds);
      _changes = await _database.getAllChanges();
    });
  }

  Future<void> addNote(String title, String content) async {
    await _runDatabaseOperation(() async {
      final note = await _database.insertNote(title: title, content: content);
      _notes = [note, ..._notes];
      _changes = await _database.getAllChanges();
    });
  }

  Future<void> updateNote(Note note, String title, String content) async {
    await _runDatabaseOperation(() async {
      final updatedNote = await _database.updateNote(
        note,
        title: title,
        content: content,
      );
      final index = _notes.indexWhere((item) => item.id == note.id);
      if (index >= 0) {
        _notes[index] = updatedNote;
      }
      _changes = await _database.getAllChanges();
    });
  }

  Future<void> deleteNote(Note note) async {
    await _runDatabaseOperation(() async {
      await _database.deleteNote(note);
      _notes.removeWhere((item) => item.id == note.id);
      _changes = await _database.getAllChanges();
    });
  }

  Future<void> _runDatabaseOperation(Future<void> Function() operation) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await operation();
      notifyListeners();
    } on Object catch (error) {
      _errorMessage = 'Database operation failed: $error';
      notifyListeners();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
