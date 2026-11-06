enum ChangeLogState {
  pending('pending'),
  synced('synced'),
  superseded('superseded');

  const ChangeLogState(this.value);

  final String value;

  static ChangeLogState fromValue(String value) =>
      ChangeLogState.values.firstWhere(
        (state) => state.value == value,
        orElse: () => throw FormatException('Unknown change-log state: $value'),
      );
}

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
    this.state,
    this.supersededBy,
    this.resolutionId,
  });

  final String id;
  final String recordId;
  final String operation;
  final int baseVersion;
  final int version;
  final DateTime timestamp;
  final String payload;
  final bool synced;
  final ChangeLogState? state;
  final String? supersededBy;
  final String? resolutionId;

  ChangeLogState get effectiveState =>
      state ?? (synced ? ChangeLogState.synced : ChangeLogState.pending);
}
