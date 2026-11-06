import 'package:flutter/material.dart';

import '../models/note.dart';

class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
  });

  final Note note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isSynced = note.syncStatus == NoteSyncStatus.synced;
    final statusColor = isSynced ? const Color(0xFF059669) : Colors.orange.shade700;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.grey.shade400),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                note.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade600, height: 1.4),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.schedule, size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 5),
                  Text(
                    _relativeTime(note.updatedAt),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                  const Spacer(),
                  Icon(
                    isSynced ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
                    size: 15,
                    color: statusColor,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isSynced ? 'Synced' : 'Pending',
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _relativeTime(DateTime time) {
    final difference = DateTime.now().difference(time);
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }
}
