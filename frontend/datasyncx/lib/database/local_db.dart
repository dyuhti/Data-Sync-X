import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/note.dart';
import '../models/change_log.dart';

class LocalDatabase {
  LocalDatabase._();

  static final LocalDatabase instance = LocalDatabase._();
  static const _databaseName = 'datasyncx.db';
  static const _databaseVersion = 2;
  static const _notesTable = 'notes';
  static const _changeLogTable = 'change_log';
  static const _uuid = Uuid();

  Database? _database;
  Future<Database>? _databaseFuture;

  Future<Database> get database async {
    if (_database != null) return _database!;
    if (_databaseFuture != null) return _databaseFuture!;
    _databaseFuture = _openDatabase();
    return _databaseFuture!;
  }

  Future<Database> _openDatabase() async {
    final databasesPath = await getDatabasesPath();
    final database = await openDatabase(
      join(databasesPath, _databaseName),
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    _database = database;
    await _seedIfEmpty(database);
    return database;
  }

  Future<void> initialize() async {
    await database;
  }

  Future<void> _onCreate(Database database, int version) async {
    await database.execute('''
      CREATE TABLE $_notesTable (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        version INTEGER NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await _createChangeLogTable(database);
  }

  Future<void> _onUpgrade(Database database, int oldVersion, int newVersion) async {
    if (oldVersion < 1) {
      await _onCreate(database, newVersion);
    } else if (oldVersion < 2) {
      await _createChangeLogTable(database);
    }
  }

  Future<void> _createChangeLogTable(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE $_changeLogTable (
        id TEXT PRIMARY KEY NOT NULL,
        record_id TEXT NOT NULL,
        operation TEXT NOT NULL CHECK (operation IN ('CREATE', 'UPDATE', 'DELETE')),
        base_version INTEGER NOT NULL,
        version INTEGER NOT NULL,
        timestamp TEXT NOT NULL,
        payload TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0 CHECK (synced IN (0, 1))
      )
    ''');
    await database.execute(
      'CREATE INDEX idx_change_log_record_id ON $_changeLogTable(record_id)',
    );
    await database.execute(
      'CREATE INDEX idx_change_log_synced ON $_changeLogTable(synced)',
    );
  }

  Future<void> _seedIfEmpty(Database database) async {
    final count = Sqflite.firstIntValue(
      await database.rawQuery('SELECT COUNT(*) FROM $_notesTable'),
    );
    if (count != 0) return;

    final now = DateTime.now();
    final samples = [
      Note(
        id: _uuid.v4(),
        title: 'Project kickoff notes',
        content: 'Outline the first sprint goals and align with the team.',
        version: 1,
        updatedAt: now.subtract(const Duration(minutes: 18)),
        syncStatus: NoteSyncStatus.synced,
      ),
      Note(
        id: _uuid.v4(),
        title: 'Ideas for weekend',
        content: 'Try the new coffee shop and take a long walk by the lake.',
        version: 1,
        updatedAt: now.subtract(const Duration(hours: 2)),
        syncStatus: NoteSyncStatus.pending,
      ),
      Note(
        id: _uuid.v4(),
        title: 'Reading list',
        content: 'Add books about design systems, productivity, and mindfulness.',
        version: 1,
        updatedAt: now.subtract(const Duration(days: 1)),
        syncStatus: NoteSyncStatus.synced,
      ),
    ];
    await database.transaction((transaction) async {
      for (final note in samples) {
        await transaction.insert(_notesTable, _toMap(note));
      }
    });
  }

  Future<Note> insertNote({
    required String title,
    required String content,
  }) async {
    final note = Note(
      id: _uuid.v4(),
      title: title,
      content: content,
      version: 1,
      updatedAt: DateTime.now(),
      syncStatus: NoteSyncStatus.pending,
    );
    final database = await this.database;
    await database.transaction((transaction) async {
      await transaction.insert(_notesTable, _toMap(note));
      await insertChangeLog(
        recordId: note.id,
        operation: 'CREATE',
        baseVersion: 0,
        version: note.version,
        payload: _notePayload(note),
        executor: transaction,
      );
    });
    return note;
  }

  Future<List<Note>> getAllNotes() async {
    final database = await this.database;
    final rows = await database.query(
      _notesTable,
      where: 'is_deleted = ?',
      whereArgs: [0],
      orderBy: 'updated_at DESC',
    );
    return rows.map(_fromMap).toList();
  }

  Future<Note?> getNoteById(String id) async {
    final database = await this.database;
    final rows = await database.query(
      _notesTable,
      where: 'id = ? AND is_deleted = ?',
      whereArgs: [id, 0],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromMap(rows.first);
  }

  Future<Note> updateNote(
    Note note, {
    required String title,
    required String content,
  }) async {
    final updatedNote = Note(
      id: note.id,
      title: title,
      content: content,
      version: note.version + 1,
      updatedAt: DateTime.now(),
      syncStatus: NoteSyncStatus.pending,
    );
    final database = await this.database;
    await database.transaction((transaction) async {
      final changed = await transaction.update(
        _notesTable,
        _toMap(updatedNote),
        where: 'id = ? AND is_deleted = ?',
        whereArgs: [note.id, 0],
      );
      if (changed != 1) {
        throw StateError('Note ${note.id} was not found.');
      }
      await insertChangeLog(
        recordId: updatedNote.id,
        operation: 'UPDATE',
        baseVersion: note.version,
        version: updatedNote.version,
        payload: _notePayload(updatedNote),
        executor: transaction,
      );
    });
    return updatedNote;
  }

  Future<void> deleteNote(Note note) async {
    final database = await this.database;
    final deletedNote = Note(
      id: note.id,
      title: note.title,
      content: note.content,
      version: note.version + 1,
      updatedAt: DateTime.now(),
      syncStatus: NoteSyncStatus.pending,
    );
    await database.transaction((transaction) async {
      final changed = await transaction.update(
        _notesTable,
        {
          ..._toMap(deletedNote),
          'is_deleted': 1,
        },
        where: 'id = ? AND is_deleted = ?',
        whereArgs: [note.id, 0],
      );
      if (changed != 1) {
        throw StateError('Note ${note.id} was not found.');
      }
      await insertChangeLog(
        recordId: deletedNote.id,
        operation: 'DELETE',
        baseVersion: note.version,
        version: deletedNote.version,
        payload: jsonEncode({..._notePayloadMap(deletedNote), 'is_deleted': true}),
        executor: transaction,
      );
    });
  }

  Future<ChangeLog> insertChangeLog({
    required String recordId,
    required String operation,
    required int baseVersion,
    required int version,
    required String payload,
    DatabaseExecutor? executor,
  }) async {
    final change = ChangeLog(
      id: _uuid.v4(),
      recordId: recordId,
      operation: operation,
      baseVersion: baseVersion,
      version: version,
      timestamp: DateTime.now(),
      payload: payload,
      synced: false,
    );
    final target = executor ?? await database;
    await target.insert(_changeLogTable, _changeToMap(change));
    return change;
  }

  Future<List<ChangeLog>> getPendingChanges() async {
    final database = await this.database;
    final rows = await database.query(
      _changeLogTable,
      where: 'synced = ?',
      whereArgs: [0],
      orderBy: 'timestamp ASC, rowid ASC',
    );
    return rows.map(_changeFromMap).toList();
  }

  Future<List<ChangeLog>> getAllChanges() async {
    final database = await this.database;
    final rows = await database.query(
      _changeLogTable,
      orderBy: 'timestamp ASC, rowid ASC',
    );
    return rows.map(_changeFromMap).toList();
  }

  Future<int> getPendingChangesCount() async {
    final database = await this.database;
    final result = await database.rawQuery(
      'SELECT COUNT(*) AS count FROM $_changeLogTable WHERE synced = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> markChangesAsSynced(Iterable<String> operationIds) async {
    final ids = operationIds.toList();
    if (ids.isEmpty) return;
    final database = await this.database;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await database.update(
      _changeLogTable,
      {'synced': 1},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  Future<int> clearSyncedChanges() async {
    final database = await this.database;
    return database.delete(_changeLogTable, where: 'synced = ?', whereArgs: [1]);
  }

  Map<String, Object?> _toMap(Note note) => {
        'id': note.id,
        'title': note.title,
        'content': note.content,
        'version': note.version,
        'updated_at': note.updatedAt.toIso8601String(),
        'sync_status': note.syncStatus.name,
        'is_deleted': 0,
      };

  String _notePayload(Note note) => jsonEncode(_notePayloadMap(note));

  Map<String, Object?> _notePayloadMap(Note note) => {
        'id': note.id,
        'title': note.title,
        'content': note.content,
        'version': note.version,
        'updated_at': note.updatedAt.toIso8601String(),
        'sync_status': note.syncStatus.name,
        'is_deleted': false,
      };

  Map<String, Object?> _changeToMap(ChangeLog change) => {
        'id': change.id,
        'record_id': change.recordId,
        'operation': change.operation,
        'base_version': change.baseVersion,
        'version': change.version,
        'timestamp': change.timestamp.toIso8601String(),
        'payload': change.payload,
        'synced': change.synced ? 1 : 0,
      };

  ChangeLog _changeFromMap(Map<String, Object?> map) => ChangeLog(
        id: map['id']! as String,
        recordId: map['record_id']! as String,
        operation: map['operation']! as String,
        baseVersion: map['base_version']! as int,
        version: map['version']! as int,
        timestamp: DateTime.parse(map['timestamp']! as String),
        payload: map['payload']! as String,
        synced: map['synced']! as int == 1,
      );

  Note _fromMap(Map<String, Object?> map) => Note(
        id: map['id']! as String,
        title: map['title']! as String,
        content: map['content']! as String,
        version: map['version']! as int,
        updatedAt: DateTime.parse(map['updated_at']! as String),
        syncStatus: NoteSyncStatus.values.byName(map['sync_status']! as String),
      );
}
