import 'dart:convert';

import 'change_log.dart';

enum ConflictType {
  updateUpdate('UPDATE_UPDATE'),
  updateDelete('UPDATE_DELETE'),
  duplicateInsert('DUPLICATE_INSERT');

  const ConflictType(this.value);

  final String value;

  static ConflictType fromValue(String value) => ConflictType.values.firstWhere(
    (type) => type.value == value,
    orElse: () => throw FormatException('Unknown conflict type: $value'),
  );
}

enum ResolutionStatus {
  unresolved('unresolved'),
  resolved('resolved');

  const ResolutionStatus(this.value);

  final String value;

  static ResolutionStatus fromValue(String value) =>
      ResolutionStatus.values.firstWhere(
        (status) => status.value == value,
        orElse: () =>
            throw FormatException('Unknown resolution status: $value'),
      );
}

enum ConflictResolutionStrategy {
  keepLocal('KEEP_LOCAL'),
  keepServer('KEEP_SERVER'),
  manualMerge('MANUAL_MERGE');

  const ConflictResolutionStrategy(this.value);

  final String value;

  static ConflictResolutionStrategy fromValue(String value) =>
      ConflictResolutionStrategy.values.firstWhere(
        (strategy) => strategy.value == value,
        orElse: () =>
            throw FormatException('Unknown resolution strategy: $value'),
      );
}

class Conflict {
  Conflict({
    required this.conflictId,
    required this.recordId,
    required this.conflictType,
    required this.operation,
    required this.localVersion,
    required this.remoteVersion,
    required Map<String, dynamic> localPayload,
    required Map<String, dynamic> remotePayload,
    required this.detectedAt,
    this.resolutionStatus = ResolutionStatus.unresolved,
    this.resolutionStrategy,
    this.resolvedAt,
    this.resolutionChangeId,
  }) : localPayloadJson = jsonEncode(localPayload),
       remotePayloadJson = jsonEncode(remotePayload);

  Conflict.fromDatabase({
    required this.conflictId,
    required this.recordId,
    required this.conflictType,
    required this.operation,
    required this.localVersion,
    required this.remoteVersion,
    required this.localPayloadJson,
    required this.remotePayloadJson,
    required this.detectedAt,
    required this.resolutionStatus,
    this.resolutionStrategy,
    this.resolvedAt,
    this.resolutionChangeId,
  });

  factory Conflict.fromJson(Map<String, dynamic> json) {
    return Conflict(
      conflictId: json['conflict_id'] as String,
      recordId: json['record_id'] as String,
      conflictType: ConflictType.fromValue(json['conflict_type'] as String),
      operation: json['operation'] as String,
      localVersion: json['local_version'] as int?,
      remoteVersion: json['remote_version'] as int?,
      localPayload: _decodePayload(json['local_payload']),
      remotePayload: _decodePayload(json['remote_payload']),
      detectedAt: DateTime.parse(json['detected_at'] as String),
      resolutionStatus: ResolutionStatus.fromValue(
        json['resolution_status'] as String? ?? 'unresolved',
      ),
      resolutionStrategy: json['resolution_strategy'] == null
          ? null
          : ConflictResolutionStrategy.fromValue(
              json['resolution_strategy'] as String,
            ),
      resolvedAt: json['resolved_at'] == null
          ? null
          : DateTime.parse(json['resolved_at'] as String),
      resolutionChangeId: json['resolution_change_id'] as String?,
    );
  }

  final String conflictId;
  final String recordId;
  final ConflictType conflictType;
  final String operation;
  final int? localVersion;
  final int? remoteVersion;
  final DateTime detectedAt;
  final ResolutionStatus resolutionStatus;
  final ConflictResolutionStrategy? resolutionStrategy;
  final DateTime? resolvedAt;
  final String? resolutionChangeId;
  final String localPayloadJson;
  final String remotePayloadJson;

  Map<String, dynamic> get localPayload => _decodePayload(localPayloadJson);
  Map<String, dynamic> get remotePayload => _decodePayload(remotePayloadJson);

  Map<String, Object?> toMap() => {
    'conflict_id': conflictId,
    'record_id': recordId,
    'conflict_type': conflictType.value,
    'operation': operation,
    'local_version': localVersion,
    'remote_version': remoteVersion,
    'local_payload': localPayloadJson,
    'remote_payload': remotePayloadJson,
    'detected_at': detectedAt.toIso8601String(),
    'resolution_status': resolutionStatus.value,
    'resolution_strategy': resolutionStrategy?.value,
    'resolved_at': resolvedAt?.toIso8601String(),
    'resolution_change_id': resolutionChangeId,
  };

  Map<String, dynamic> toJson() => {
    'conflict_id': conflictId,
    'record_id': recordId,
    'conflict_type': conflictType.value,
    'operation': operation,
    'local_version': localVersion,
    'remote_version': remoteVersion,
    'local_payload': localPayload,
    'remote_payload': remotePayload,
    'detected_at': detectedAt.toIso8601String(),
    'resolution_status': resolutionStatus.value,
    'resolution_strategy': resolutionStrategy?.value,
    'resolved_at': resolvedAt?.toIso8601String(),
    'resolution_change_id': resolutionChangeId,
  };

  Conflict copyWith({
    ResolutionStatus? resolutionStatus,
    ConflictResolutionStrategy? resolutionStrategy,
    DateTime? resolvedAt,
    String? resolutionChangeId,
  }) =>
      Conflict.fromDatabase(
        conflictId: conflictId,
        recordId: recordId,
        conflictType: conflictType,
        operation: operation,
        localVersion: localVersion,
        remoteVersion: remoteVersion,
        localPayloadJson: localPayloadJson,
        remotePayloadJson: remotePayloadJson,
        detectedAt: detectedAt,
        resolutionStatus: resolutionStatus ?? this.resolutionStatus,
        resolutionStrategy: resolutionStrategy ?? this.resolutionStrategy,
        resolvedAt: resolvedAt ?? this.resolvedAt,
        resolutionChangeId: resolutionChangeId ?? this.resolutionChangeId,
      );

  static Map<String, dynamic> _decodePayload(Object? payload) {
    final decoded = payload is String ? jsonDecode(payload) : payload;
    if (decoded is! Map) {
      throw const FormatException('Conflict payload must be a JSON object.');
    }
    return Map<String, dynamic>.from(decoded);
  }
}

class ConflictResolutionResult {
  const ConflictResolutionResult({
    required this.conflict,
    this.resolutionChange,
  });

  final Conflict conflict;
  final ChangeLog? resolutionChange;
}
