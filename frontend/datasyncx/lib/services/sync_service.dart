import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../database/local_db.dart';
import '../models/change_log.dart';
import '../models/conflict.dart';

class SyncResult {
  const SyncResult({
    required this.successfulOperations,
    required this.failedOperations,
    required this.remainingPending,
    this.error,
  });

  final int successfulOperations;
  final int failedOperations;
  final int remainingPending;
  final String? error;

  bool get succeeded => failedOperations == 0 && error == null;
}

class SyncService {
  SyncService({
    LocalDatabase? database,
    http.Client? client,
    String? baseUrl,
    this._timeout = const Duration(seconds: 15),
  }) : _database = database ?? LocalDatabase.instance,
       _client = client ?? http.Client(),
       _baseUrl = (baseUrl ?? ApiConfig.baseUrl).replaceFirst(
         RegExp(r'/$'),
         '',
       );

  final LocalDatabase _database;
  final http.Client _client;
  final String _baseUrl;
  final Duration _timeout;
  bool _isSyncing = false;

  bool get isSyncing => _isSyncing;

  Future<SyncResult> syncPendingChanges() async {
    if (_isSyncing) {
      final remaining = await _database.getPendingChangesCount();
      return SyncResult(
        successfulOperations: 0,
        failedOperations: 0,
        remainingPending: remaining,
        error: 'Synchronization is already in progress.',
      );
    }

    _isSyncing = true;
    var successful = 0;
    var failed = 0;
    String? error;
    try {
      final pending = await _database.getPendingChanges();
      for (final change in pending) {
        try {
          final unresolvedConflicts = await _database.getUnresolvedConflicts();
          if (unresolvedConflicts.any(
            (conflict) => conflict.recordId == change.recordId,
          )) {
            throw ConflictException(
              'Synchronization is blocked by an unresolved conflict for '
              '${change.recordId}.',
            );
          }
          await _sendChange(change);
          await _database.markChangesAsSynced([change.id]);
          successful++;
        } on Object catch (exception) {
          failed++;
          error = exception.toString();
          // Keep the queue ordered: later operations may depend on this one.
          break;
        }
      }
    } finally {
      _isSyncing = false;
    }

    return SyncResult(
      successfulOperations: successful,
      failedOperations: failed,
      remainingPending: await _database.getPendingChangesCount(),
      error: error,
    );
  }

  Future<void> _sendChange(ChangeLog change) async {
    final decoded = jsonDecode(change.payload);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Change payload must be a JSON object.');
    }
    final payload = Map<String, dynamic>.from(decoded);
    if (payload['id'] != change.recordId) {
      throw const FormatException(
        'Change payload id does not match record id.',
      );
    }

    final uri = Uri.parse('$_baseUrl/api/notes/${change.recordId}');
    http.Response response;
    switch (change.operation) {
      case 'CREATE':
        response = await _request(
          () => _client.post(
            Uri.parse('$_baseUrl/api/notes'),
            headers: _headers,
            body: jsonEncode(payload),
          ),
        );
        if (response.statusCode == 409) {
          final decoded = jsonDecode(response.body);
          if (decoded is! Map || decoded['status'] != 'conflict') {
            await _acceptEquivalentRemoteNote(change, payload);
            return;
          }
        }
        break;
      case 'UPDATE':
        response = await _request(
          () => _client.put(
            uri,
            headers: _headers,
            body: jsonEncode({...payload, 'base_version': change.baseVersion}),
          ),
        );
        break;
      case 'DELETE':
        response = await _request(
          () => _client.delete(
            uri,
            headers: _headers,
            body: jsonEncode({'base_version': change.baseVersion}),
          ),
        );
        if (response.statusCode == 404) {
          return;
        }
        break;
      default:
        throw FormatException(
          'Unsupported change operation: ${change.operation}',
        );
    }
    if (response.statusCode == 409) {
      await _storeConflict(response, change);
    }
    _validateResponse(response, expectedId: change.recordId);
  }

  Future<void> _storeConflict(http.Response response, ChangeLog change) async {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Conflict response must be a JSON object.');
    }
    final body = Map<String, dynamic>.from(decoded);
    if (body['status'] != 'conflict' ||
        body['conflict_type'] is! String ||
        body['record_id'] != change.recordId ||
        body['operation'] != change.operation ||
        !_isNullableInt(body['local_version']) ||
        !_isNullableInt(body['remote_version']) ||
        body['local_payload'] is! Map ||
        body['remote_payload'] is! Map) {
      throw const FormatException(
        'Conflict response does not match the conflict API contract.',
      );
    }
    final conflictType = ConflictType.fromValue(
      body['conflict_type'] as String,
    );
    await _database.insertConflict(
      recordId: body['record_id'] as String,
      conflictType: conflictType,
      operation: body['operation'] as String,
      localVersion: body['local_version'] as int?,
      remoteVersion: body['remote_version'] as int?,
      localPayload: Map<String, dynamic>.from(body['local_payload'] as Map),
      remotePayload: Map<String, dynamic>.from(body['remote_payload'] as Map),
    );
  }

  bool _isNullableInt(Object? value) =>
      value == null || (value is int && value is! bool);

  Future<void> _acceptEquivalentRemoteNote(
    ChangeLog change,
    Map<String, dynamic> local,
  ) async {
    final response = await _request(
      () => _client.get(Uri.parse('$_baseUrl/api/notes/${change.recordId}')),
    );
    if (response.statusCode != 200) {
      throw HttpException(
        'CREATE was rejected with HTTP 409 and the remote note could not be verified '
        '(HTTP ${response.statusCode}).',
      );
    }
    final remote = _validatedNote(response, expectedId: change.recordId);
    final sameContent =
        remote['title'] == local['title'] &&
        remote['content'] == local['content'] &&
        remote['version'] == local['version'] &&
        remote['is_deleted'] == (local['is_deleted'] ?? false);
    if (!sameContent) {
      throw const ConflictException(
        'CREATE was rejected because the remote note differs from the local operation.',
      );
    }
  }

  Future<http.Response> _request(
    Future<http.Response> Function() request,
  ) async {
    try {
      return await request().timeout(_timeout);
    } on Object catch (error) {
      throw HttpException('Request failed: $error');
    }
  }

  void _validateResponse(http.Response response, {required String expectedId}) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Server rejected the operation (HTTP ${response.statusCode}): '
        '${_errorMessage(response)}',
      );
    }
    _validatedNote(response, expectedId: expectedId);
  }

  Map<String, dynamic> _validatedNote(
    http.Response response, {
    required String expectedId,
  }) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> ||
        decoded['status'] != 'ok' ||
        decoded['note'] is! Map<String, dynamic>) {
      throw const FormatException(
        'Server response does not match the note API contract.',
      );
    }
    final note = Map<String, dynamic>.from(decoded['note'] as Map);
    if (note['id'] != expectedId ||
        note['title'] is! String ||
        note['content'] is! String ||
        note['version'] is! int ||
        note['updated_at'] is! String ||
        note['is_deleted'] is! bool) {
      throw const FormatException('Server returned an invalid note.');
    }
    return note;
  }

  String _errorMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['message'] is String) {
        return body['message'] as String;
      }
    } on Object {
      // The status code is still useful when the server does not return JSON.
    }
    return response.reasonPhrase ?? 'Unknown server error';
  }

  Map<String, String> get _headers => const {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };
}

class HttpException implements Exception {
  const HttpException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ConflictException implements Exception {
  const ConflictException(this.message);

  final String message;

  @override
  String toString() => message;
}
