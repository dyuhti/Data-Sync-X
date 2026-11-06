import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/note.dart';
import '../models/change_log.dart';
import '../models/conflict.dart';

class LocalDatabase {
  LocalDatabase._([this._databasePath]);

  static final LocalDatabase instance = LocalDatabase._();
  static LocalDatabase forTesting(String databasePath) =>
      LocalDatabase._(databasePath);
  static Future<void> resetForTesting() => instance.close();
  static const _databaseName = 'datasyncx.db';
  static const _databaseVersion = 4;
  static const _notesTable = 'notes';
  static const _changeLogTable = 'change_log';
  static const _conflictsTable = 'conflicts';
  static const _uuid = Uuid();

  final String? _databasePath;
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
      _databasePath ?? join(databasesPath, _databaseName),
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    _database = database;
    await ensureInitialUploadChanges();
    await reconcileNoteSyncStatuses();
    return database;
  }

  Future<void> close() async {
    final database = _database;
    _database = null;
    _databaseFuture = null;
    if (database != null) {
      await database.close();
    }
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
    await _createConflictsTable(database);
    await _createConflictChangesTable(database);
  }

  Future<void> _onUpgrade(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 1) {
      await _onCreate(database, newVersion);
    } else {
      if (oldVersion < 2) {
        await _createChangeLogTable(database);
      }
      if (oldVersion < 3) {
        await _createConflictsTable(database);
      }
      if (oldVersion < 4) {
        await _upgradeToVersionFour(database);
      }
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
        synced INTEGER NOT NULL DEFAULT 0 CHECK (synced IN (0, 1)),
        state TEXT NOT NULL DEFAULT 'pending'
          CHECK (state IN ('pending', 'synced', 'superseded')),
        superseded_by TEXT,
        resolution_id TEXT
      )
    ''');
    await database.execute(
      'CREATE INDEX idx_change_log_record_id ON $_changeLogTable(record_id)',
    );
    await database.execute(
      'CREATE INDEX idx_change_log_synced ON $_changeLogTable(synced)',
    );
  }

  Future<void> _createConflictsTable(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE $_conflictsTable (
        conflict_id TEXT PRIMARY KEY NOT NULL,
        record_id TEXT NOT NULL,
        conflict_type TEXT NOT NULL,
        operation TEXT NOT NULL,
        local_version INTEGER,
        remote_version INTEGER,
        local_payload TEXT NOT NULL,
        remote_payload TEXT NOT NULL,
        detected_at TEXT NOT NULL,
        resolution_status TEXT NOT NULL DEFAULT 'unresolved'
        ,resolution_strategy TEXT
        ,resolved_at TEXT
        ,resolution_change_id TEXT
      )
    ''');
    await database.execute(
      'CREATE INDEX idx_conflicts_record_id ON $_conflictsTable(record_id)',
    );
    await database.execute(
      'CREATE INDEX idx_conflicts_resolution_status '
      'ON $_conflictsTable(resolution_status)',
    );
    await database.execute('''
      CREATE UNIQUE INDEX idx_conflicts_unresolved_identity
      ON $_conflictsTable(
        record_id,
        conflict_type,
        operation,
        local_version,
        remote_version
      )
      WHERE resolution_status = 'unresolved'
    ''');
  }

  Future<void> _upgradeToVersionFour(DatabaseExecutor database) async {
    await _addColumnIfMissing(
      database,
      _changeLogTable,
      'state',
      "TEXT NOT NULL DEFAULT 'pending' "
          "CHECK (state IN ('pending', 'synced', 'superseded'))",
    );
    await _addColumnIfMissing(
      database,
      _changeLogTable,
      'superseded_by',
      'TEXT',
    );
    await _addColumnIfMissing(
      database,
      _changeLogTable,
      'resolution_id',
      'TEXT',
    );
    await database.execute(
      "UPDATE $_changeLogTable SET state = CASE WHEN synced = 1 "
      "THEN 'synced' ELSE 'pending' END",
    );
    await _addColumnIfMissing(
      database,
      _conflictsTable,
      'resolution_strategy',
      'TEXT',
    );
    await _addColumnIfMissing(database, _conflictsTable, 'resolved_at', 'TEXT');
    await _addColumnIfMissing(
      database,
      _conflictsTable,
      'resolution_change_id',
      'TEXT',
    );
    final conflictChanges = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name = 'conflict_changes'",
    );
    if (conflictChanges.isEmpty) {
      await _createConflictChangesTable(database);
    }
    final stateIndexes = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index' "
      "AND name = 'idx_change_log_state'",
    );
    if (stateIndexes.isEmpty) {
      await database.execute(
        'CREATE INDEX idx_change_log_state ON $_changeLogTable(state)',
      );
    }
  }

  Future<void> _addColumnIfMissing(
    DatabaseExecutor database,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await database.rawQuery('PRAGMA table_info($table)');
    if (columns.any((row) => row['name'] == column)) return;
    await database.execute(
      'ALTER TABLE $table ADD COLUMN $column $definition',
    );
  }

  Future<void> _createConflictChangesTable(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE conflict_changes (
        conflict_id TEXT NOT NULL,
        change_id TEXT NOT NULL,
        relationship TEXT NOT NULL
          CHECK (relationship IN ('source', 'dependent', 'resolution')),
        PRIMARY KEY (conflict_id, change_id)
      )
    ''');
    await database.execute(
      'CREATE INDEX idx_conflict_changes_change_id '
      'ON conflict_changes(change_id)',
    );
  }

  Future<void> ensureInitialUploadChanges() async {
    final database = await this.database;
    await database.transaction((transaction) async {
      final notes = await transaction.query(
        _notesTable,
        where:
            '''
          is_deleted = 0
          AND NOT EXISTS (
            SELECT 1
            FROM $_changeLogTable
            WHERE $_changeLogTable.record_id = $_notesTable.id
              AND $_changeLogTable.operation = 'CREATE'
          )
          AND NOT EXISTS (
            SELECT 1
            FROM $_changeLogTable
            WHERE $_changeLogTable.record_id = $_notesTable.id
              AND $_changeLogTable.state = 'synced'
          )
        ''',
      );

      for (final row in notes) {
        final note = _fromMap(row);
        await insertChangeLog(
          recordId: note.id,
          operation: 'CREATE',
          baseVersion: 0,
          version: note.version,
          payload: _notePayload(note),
          executor: transaction,
        );
      }
    });
  }

  Future<void> reconcileNoteSyncStatuses() async {
    final database = await this.database;
    await database.transaction((transaction) async {
      await transaction.rawUpdate(
        '''
        UPDATE $_notesTable
        SET sync_status = CASE
          WHEN EXISTS (
            SELECT 1
            FROM $_changeLogTable
            WHERE $_changeLogTable.record_id = $_notesTable.id
              AND $_changeLogTable.state = 'pending'
          ) THEN ?
          ELSE ?
        END
        ''',
        [NoteSyncStatus.pending.name, NoteSyncStatus.synced.name],
      );
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

  Future<int> mergeRemoteNotes(List<Map<String, dynamic>> remoteNotes) async {
    final database = await this.database;
    var changedNotes = 0;
    await database.transaction((transaction) async {
      for (final remote in remoteNotes) {
        final id = remote['id']! as String;
        final localRows = await transaction.query(
          _notesTable,
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (localRows.isNotEmpty) {
          final pendingRows = await transaction.query(
            _changeLogTable,
            columns: ['id'],
            where: 'record_id = ? AND state = ?',
            whereArgs: [id, ChangeLogState.pending.value],
            limit: 1,
          );
          if (pendingRows.isNotEmpty) continue;

          final localVersion = localRows.first['version']! as int;
          final remoteVersion = remote['version']! as int;
          if (remoteVersion <= localVersion) continue;
        }

        await transaction.insert(
          _notesTable,
          {
            'id': id,
            'title': remote['title']! as String,
            'content': remote['content']! as String,
            'version': remote['version']! as int,
            'updated_at': remote['updated_at']! as String,
            'sync_status': NoteSyncStatus.synced.name,
            'is_deleted': remote['is_deleted']! as bool ? 1 : 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        changedNotes++;
      }
    });
    return changedNotes;
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
        {..._toMap(deletedNote), 'is_deleted': 1},
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
        payload: jsonEncode({
          ..._notePayloadMap(deletedNote),
          'is_deleted': true,
        }),
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
      where: 'state = ?',
      whereArgs: [ChangeLogState.pending.value],
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
      'SELECT COUNT(*) AS count FROM $_changeLogTable WHERE state = ?',
      [ChangeLogState.pending.value],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> markChangesAsSynced(Iterable<String> operationIds) async {
    final ids = operationIds.toList();
    if (ids.isEmpty) return;
    final database = await this.database;
    await database.transaction((transaction) async {
      for (final operationId in ids) {
        final changes = await transaction.query(
          _changeLogTable,
          columns: ['record_id'],
          where: 'id = ?',
          whereArgs: [operationId],
          limit: 1,
        );
        if (changes.isEmpty) continue;

        final recordId = changes.first['record_id']! as String;
        await transaction.update(
          _changeLogTable,
          {'synced': 1, 'state': ChangeLogState.synced.value},
          where: 'id = ?',
          whereArgs: [operationId],
        );
        final pending = await transaction.query(
          _changeLogTable,
          columns: ['id'],
          where: 'record_id = ? AND state = ?',
          whereArgs: [recordId, ChangeLogState.pending.value],
          limit: 1,
        );
        await transaction.update(
          _notesTable,
          {
            'sync_status': pending.isEmpty
                ? NoteSyncStatus.synced.name
                : NoteSyncStatus.pending.name,
          },
          where: 'id = ?',
          whereArgs: [recordId],
        );
      }
    });
  }

  Future<int> clearSyncedChanges() async {
    final database = await this.database;
    return database.delete(
      _changeLogTable,
      where: "state = ?",
      whereArgs: [ChangeLogState.synced.value],
    );
  }

  Future<Conflict> insertConflict({
    required String recordId,
    required ConflictType conflictType,
    required String operation,
    required int? localVersion,
    required int? remoteVersion,
    required Map<String, dynamic> localPayload,
    required Map<String, dynamic> remotePayload,
    DateTime? detectedAt,
  }) async {
    final database = await this.database;
    final existing = await _findUnresolvedConflict(
      database,
      recordId: recordId,
      conflictType: conflictType,
      operation: operation,
      localVersion: localVersion,
      remoteVersion: remoteVersion,
    );
    if (existing != null) return existing;

    final conflict = Conflict(
      conflictId: _uuid.v4(),
      recordId: recordId,
      conflictType: conflictType,
      operation: operation,
      localVersion: localVersion,
      remoteVersion: remoteVersion,
      localPayload: localPayload,
      remotePayload: remotePayload,
      detectedAt: detectedAt ?? DateTime.now(),
    );
    await database.insert(_conflictsTable, conflict.toMap());
    return conflict;
  }

  Future<ConflictResolutionResult> resolveConflict({
    required String conflictId,
    required ConflictResolutionStrategy strategy,
    Map<String, dynamic>? mergedPayload,
  }) async {
    final database = await this.database;
    late Conflict resolvedConflict;
    ChangeLog? resolutionChange;
    await database.transaction((transaction) async {
      final conflictRows = await transaction.query(
        _conflictsTable,
        where: 'conflict_id = ?',
        whereArgs: [conflictId],
        limit: 1,
      );
      if (conflictRows.isEmpty) {
        throw StateError('Conflict $conflictId was not found.');
      }
      final conflict = _conflictFromMap(conflictRows.first);
      if (conflict.resolutionStatus != ResolutionStatus.unresolved) {
        throw StateError('Conflict $conflictId has already been resolved.');
      }

      final pendingRows = await transaction.query(
        _changeLogTable,
        where: 'record_id = ? AND state = ?',
        whereArgs: [conflict.recordId, ChangeLogState.pending.value],
        orderBy: 'timestamp ASC, rowid ASC',
      );
      final pendingChanges = pendingRows.map(_changeFromMap).toList();
      for (final change in pendingChanges) {
        await transaction.insert('conflict_changes', {
          'conflict_id': conflictId,
          'change_id': change.id,
          'relationship': change.version == conflict.localVersion
              ? 'source'
              : 'dependent',
        });
      }

      final remotePayload = _validatedResolutionPayload(
        conflict.remotePayload,
        recordId: conflict.recordId,
      );
      final localRow = await transaction.query(
        _notesTable,
        where: 'id = ?',
        whereArgs: [conflict.recordId],
        limit: 1,
      );
      final currentLocalPayload = localRow.isEmpty
          ? _validatedResolutionPayload(
              conflict.localPayload,
              recordId: conflict.recordId,
            )
          : _noteRowPayload(localRow.first);

      Map<String, dynamic> finalPayload;
      if (strategy == ConflictResolutionStrategy.keepServer) {
        finalPayload = remotePayload;
      } else if (strategy == ConflictResolutionStrategy.keepLocal) {
        finalPayload = currentLocalPayload;
      } else {
        if (mergedPayload == null) {
          throw const FormatException(
            'MANUAL_MERGE requires a merged payload.',
          );
        }
        finalPayload = _validatedResolutionPayload(
          mergedPayload,
          recordId: conflict.recordId,
        );
      }

      final remoteVersion = conflict.remoteVersion ?? remotePayload['version'];
      if (remoteVersion is! int || remoteVersion < 0) {
        throw const FormatException(
          'Conflict resolution requires a valid remote version.',
        );
      }

      for (final change in pendingChanges) {
        await transaction.update(
          _changeLogTable,
          {
            'state': ChangeLogState.superseded.value,
            'synced': 0,
            'superseded_by': null,
            'resolution_id': conflictId,
          },
          where: 'id = ? AND state = ?',
          whereArgs: [change.id, ChangeLogState.pending.value],
        );
      }

      if (strategy != ConflictResolutionStrategy.keepServer) {
        final isDeleted = finalPayload['is_deleted'] as bool;
        final resolutionVersion = remoteVersion + 1;
        final operation = isDeleted ? 'DELETE' : 'UPDATE';
        final resolutionPayload = <String, dynamic>{
          'id': conflict.recordId,
          'title': finalPayload['title'],
          'content': finalPayload['content'],
          'version': resolutionVersion,
          'updated_at': finalPayload['updated_at'],
          'is_deleted': isDeleted,
        };
        resolutionChange = await _insertResolutionChangeLog(
          transaction,
          conflictId: conflictId,
          recordId: conflict.recordId,
          operation: operation,
          baseVersion: remoteVersion,
          version: resolutionVersion,
          payload: jsonEncode(resolutionPayload),
        );
        for (final change in pendingChanges) {
          await transaction.update(
            _changeLogTable,
            {'superseded_by': resolutionChange!.id},
            where: 'id = ? AND state = ?',
            whereArgs: [change.id, ChangeLogState.superseded.value],
          );
        }
        await transaction.insert(
          'conflict_changes',
          {
            'conflict_id': conflictId,
            'change_id': resolutionChange!.id,
            'relationship': 'resolution',
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        final noteMap = {
          ...resolutionPayload,
          'sync_status': NoteSyncStatus.pending.name,
          'is_deleted': isDeleted ? 1 : 0,
        };
        await transaction.update(
          _notesTable,
          noteMap,
          where: 'id = ?',
          whereArgs: [conflict.recordId],
        );
      } else {
        await transaction.update(
          _notesTable,
          {
            ...remotePayload,
            'sync_status': NoteSyncStatus.synced.name,
            'is_deleted': remotePayload['is_deleted'] == true ? 1 : 0,
          },
          where: 'id = ?',
          whereArgs: [conflict.recordId],
        );
      }

      final resolvedAt = DateTime.now();
      await transaction.update(
        _conflictsTable,
        {
          'resolution_status': ResolutionStatus.resolved.value,
          'resolution_strategy': strategy.value,
          'resolved_at': resolvedAt.toIso8601String(),
          'resolution_change_id': resolutionChange?.id,
        },
        where: 'conflict_id = ? AND resolution_status = ?',
        whereArgs: [conflictId, ResolutionStatus.unresolved.value],
      );
      resolvedConflict = Conflict.fromDatabase(
        conflictId: conflict.conflictId,
        recordId: conflict.recordId,
        conflictType: conflict.conflictType,
        operation: conflict.operation,
        localVersion: conflict.localVersion,
        remoteVersion: conflict.remoteVersion,
        localPayloadJson: conflict.localPayloadJson,
        remotePayloadJson: conflict.remotePayloadJson,
        detectedAt: conflict.detectedAt,
        resolutionStatus: ResolutionStatus.resolved,
        resolutionStrategy: strategy,
        resolvedAt: resolvedAt,
        resolutionChangeId: resolutionChange?.id,
      );
    });
    return ConflictResolutionResult(
      conflict: resolvedConflict,
      resolutionChange: resolutionChange,
    );
  }

  Future<List<Conflict>> getUnresolvedConflicts() async {
    final database = await this.database;
    final rows = await database.query(
      _conflictsTable,
      where: 'resolution_status = ?',
      whereArgs: [ResolutionStatus.unresolved.value],
      orderBy: 'detected_at ASC',
    );
    return rows.map(_conflictFromMap).toList();
  }

  Future<List<Conflict>> getConflictsForRecord(String recordId) async {
    final database = await this.database;
    final rows = await database.query(
      _conflictsTable,
      where: 'record_id = ?',
      whereArgs: [recordId],
      orderBy: 'detected_at ASC',
    );
    return rows.map(_conflictFromMap).toList();
  }

  Future<int> getUnresolvedConflictCount() async {
    final database = await this.database;
    final result = await database.rawQuery(
      'SELECT COUNT(*) AS count FROM $_conflictsTable '
      'WHERE resolution_status = ?',
      [ResolutionStatus.unresolved.value],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<Conflict?> getConflictById(String conflictId) async {
    final database = await this.database;
    final rows = await database.query(
      _conflictsTable,
      where: 'conflict_id = ?',
      whereArgs: [conflictId],
      limit: 1,
    );
    return rows.isEmpty ? null : _conflictFromMap(rows.first);
  }

  Future<void> markConflictResolved(String conflictId) async {
    final database = await this.database;
    await database.update(
      _conflictsTable,
      {'resolution_status': ResolutionStatus.resolved.value},
      where: 'conflict_id = ?',
      whereArgs: [conflictId],
    );
  }

  Future<ChangeLog> _insertResolutionChangeLog(
    DatabaseExecutor database, {
    required String conflictId,
    required String recordId,
    required String operation,
    required int baseVersion,
    required int version,
    required String payload,
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
      state: ChangeLogState.pending,
      resolutionId: conflictId,
    );
    await database.insert(_changeLogTable, _changeToMap(change));
    return change;
  }

  Map<String, dynamic> _validatedResolutionPayload(
    Map<String, dynamic> payload, {
    required String recordId,
  }) {
    if (payload['id'] != recordId ||
        payload['title'] is! String ||
        payload['content'] is! String) {
      throw const FormatException(
        'Resolution payload must contain the record id, title, and content.',
      );
    }
    final isDeleted = payload['is_deleted'] ?? false;
    if (isDeleted is! bool) {
      throw const FormatException('Resolution is_deleted must be a boolean.');
    }
    final version = payload['version'];
    if (version != null && (version is! int || version < 1)) {
      throw const FormatException('Resolution version must be positive.');
    }
    final updatedAt = payload['updated_at'];
    if (updatedAt != null && updatedAt is! String) {
      throw const FormatException(
        'Resolution updated_at must be a timestamp string.',
      );
    }
    return {
      ...payload,
      'is_deleted': isDeleted,
      'updated_at': updatedAt is String
          ? updatedAt
          : DateTime.now().toIso8601String(),
    };
  }

  Map<String, dynamic> _noteRowPayload(Map<String, Object?> row) => {
    'id': row['id'],
    'title': row['title'],
    'content': row['content'],
    'version': row['version'],
    'updated_at': row['updated_at'],
    'is_deleted': row['is_deleted'] == 1,
  };

  Future<Conflict?> _findUnresolvedConflict(
    DatabaseExecutor database, {
    required String recordId,
    required ConflictType conflictType,
    required String operation,
    required int? localVersion,
    required int? remoteVersion,
  }) async {
    final rows = await database.query(
      _conflictsTable,
      where: '''
        record_id = ?
        AND conflict_type = ?
        AND operation = ?
        AND resolution_status = ?
        AND ((local_version = ?) OR (local_version IS NULL AND ? IS NULL))
        AND ((remote_version = ?) OR (remote_version IS NULL AND ? IS NULL))
      ''',
      whereArgs: [
        recordId,
        conflictType.value,
        operation,
        ResolutionStatus.unresolved.value,
        localVersion,
        localVersion,
        remoteVersion,
        remoteVersion,
      ],
      limit: 1,
    );
    return rows.isEmpty ? null : _conflictFromMap(rows.first);
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
    'state': change.effectiveState.value,
    'superseded_by': change.supersededBy,
    'resolution_id': change.resolutionId,
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
    state: map['state'] == null
        ? null
        : ChangeLogState.fromValue(map['state']! as String),
    supersededBy: map['superseded_by'] as String?,
    resolutionId: map['resolution_id'] as String?,
  );

  Conflict _conflictFromMap(Map<String, Object?> map) => Conflict.fromDatabase(
    conflictId: map['conflict_id']! as String,
    recordId: map['record_id']! as String,
    conflictType: ConflictType.fromValue(map['conflict_type']! as String),
    operation: map['operation']! as String,
    localVersion: map['local_version'] as int?,
    remoteVersion: map['remote_version'] as int?,
    localPayloadJson: map['local_payload']! as String,
    remotePayloadJson: map['remote_payload']! as String,
    detectedAt: DateTime.parse(map['detected_at']! as String),
    resolutionStatus: ResolutionStatus.fromValue(
      map['resolution_status']! as String,
    ),
    resolutionStrategy: map['resolution_strategy'] == null
        ? null
        : ConflictResolutionStrategy.fromValue(
            map['resolution_strategy']! as String,
          ),
    resolvedAt: map['resolved_at'] == null
        ? null
        : DateTime.parse(map['resolved_at']! as String),
    resolutionChangeId: map['resolution_change_id'] as String?,
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
