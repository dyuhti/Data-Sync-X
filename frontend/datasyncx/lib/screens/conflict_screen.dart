import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/conflict.dart';
import '../providers/note_provider.dart';

class ConflictScreen extends StatelessWidget {
  const ConflictScreen({super.key, this.conflict});

  final Conflict? conflict;

  @override
  Widget build(BuildContext context) {
    if (conflict != null) {
      return _ConflictDetail(conflict: conflict!);
    }

    final provider = context.watch<NoteProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Conflicts')),
      body: provider.unresolvedConflicts.isEmpty
          ? const _EmptyConflicts()
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  '${provider.unresolvedConflictCount} unresolved conflict'
                  '${provider.unresolvedConflictCount == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                ...provider.unresolvedConflicts.map(
                  (item) => _ConflictListTile(conflict: item),
                ),
              ],
            ),
    );
  }
}

class _ConflictListTile extends StatelessWidget {
  const _ConflictListTile({required this.conflict});

  final Conflict conflict;

  @override
  Widget build(BuildContext context) {
    final title =
        _payloadString(conflict.localPayload, 'title') ??
        _payloadString(conflict.remotePayload, 'title') ??
        conflict.recordId;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(
          Icons.warning_amber_rounded,
          color: Colors.orange.shade700,
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${conflict.conflictType.value}  |  '
          '${_formatDateTime(conflict.detectedAt)}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ConflictScreen(conflict: conflict),
          ),
        ),
      ),
    );
  }
}

class _ConflictDetail extends StatelessWidget {
  const _ConflictDetail({required this.conflict});

  final Conflict conflict;

  @override
  Widget build(BuildContext context) {
    final title =
        _payloadString(conflict.localPayload, 'title') ??
        _payloadString(conflict.remotePayload, 'title') ??
        conflict.recordId;
    return Scaffold(
      appBar: AppBar(title: const Text('Review conflict')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange.shade800,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'This conflict requires review. Resolution will be '
                    'available in the next phase.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Note',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          _metadataCard(),
          const SizedBox(height: 16),
          _versionCard(
            'My version',
            conflict.localVersion,
            _payloadString(conflict.localPayload, 'content') ?? '',
            Colors.blue,
          ),
          const SizedBox(height: 12),
          _versionCard(
            'Server version',
            conflict.remoteVersion,
            _payloadString(conflict.remotePayload, 'content') ?? '',
            Colors.deepPurple,
          ),
        ],
      ),
    );
  }

  Widget _metadataCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _metadataRow('Conflict type', conflict.conflictType.value),
            _metadataRow('Detected', _formatDateTime(conflict.detectedAt)),
            _metadataRow('Local version', '${conflict.localVersion ?? '-'}'),
            _metadataRow('Remote version', '${conflict.remoteVersion ?? '-'}'),
            _metadataRow('Status', conflict.resolutionStatus.value),
          ],
        ),
      ),
    );
  }

  Widget _metadataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _versionCard(
    String heading,
    int? version,
    String content,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  heading,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  'Version ${version ?? '-'}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                content.isEmpty ? '(No content)' : content,
                style: const TextStyle(height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyConflicts extends StatelessWidget {
  const _EmptyConflicts();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 56,
              color: Colors.green.shade600,
            ),
            const SizedBox(height: 16),
            const Text(
              'No unresolved conflicts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Conflicts detected during synchronization will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

String? _payloadString(Map<String, dynamic> payload, String key) {
  final value = payload[key];
  return value is String ? value : null;
}

String _formatDateTime(DateTime time) =>
    time.toLocal().toString().split('.').first;
