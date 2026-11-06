enum NoteSyncStatus { synced, pending }

class Note {
  Note({
    required this.id,
    required this.title,
    required this.content,
    this.version = 1,
    required this.updatedAt,
    required this.syncStatus,
  });

  final String id;
  String title;
  String content;
  int version;
  DateTime updatedAt;
  NoteSyncStatus syncStatus;
}
