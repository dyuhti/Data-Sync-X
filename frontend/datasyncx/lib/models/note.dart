enum NoteSyncStatus { synced, pending }

class Note {
  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.updatedAt,
    required this.syncStatus,
  });

  final String id;
  String title;
  String content;
  DateTime updatedAt;
  NoteSyncStatus syncStatus;
}
