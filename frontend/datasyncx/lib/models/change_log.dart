class ChangeLog {
  const ChangeLog({
    required this.id,
    required this.recordId,
    required this.operation,
    required this.baseVersion,
    required this.version,
    required this.timestamp,
    required this.payload,
    required this.synced,
  });

  final String id;
  final String recordId;
  final String operation;
  final int baseVersion;
  final int version;
  final DateTime timestamp;
  final String payload;
  final bool synced;
}
