import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/change_log.dart';
import '../providers/note_provider.dart';
import '../widgets/connectivity_badge.dart';
import '../widgets/sync_status_card.dart';
import 'conflict_screen.dart';

class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NoteProvider>();
    final pending = provider.pendingChangesCount;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text('Synchronization', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Keep your notes up to date', style: TextStyle(color: Colors.grey.shade600)),
              const Spacer(),
              const ConnectivityBadge(compact: true),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.green.shade100),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
                  child: Icon(Icons.cloud_done_outlined, color: Colors.green.shade700),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.lastSyncError == null
                            ? 'Synchronization status'
                            : 'Synchronization needs attention',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        provider.lastSyncTime == null
                            ? 'No synchronization has run yet'
                            : 'Last run ${_formatTime(provider.lastSyncTime!)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _statCard(Icons.pending_actions, 'Pending changes', '$pending', Colors.orange.shade700),
              _statCard(Icons.list_alt, 'Total operations', '${provider.changes.length}', Colors.blue.shade700),
              _statCard(Icons.add_circle_outline, 'Creates', '${provider.createChangesCount}', Colors.teal.shade700),
              _statCard(Icons.edit_outlined, 'Updates', '${provider.updateChangesCount}', Colors.indigo.shade700),
              _statCard(Icons.delete_outline, 'Deletes', '${provider.deleteChangesCount}', Colors.red.shade600),
              _statCard(Icons.check_circle_outline, 'Synchronized', '${provider.successfulOperationsCount}', Colors.green.shade700),
              _statCard(Icons.error_outline, 'Failed', '${provider.failedOperationsCount}', Colors.red.shade700),
              _statCard(Icons.hourglass_empty, 'Remaining', '${provider.remainingPendingCount}', Colors.orange.shade700),
            ],
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: provider.isSyncing
                ? null
                : () async {
                    await provider.syncPendingChanges();
                    if (!context.mounted) return;
                    final result = provider.lastSyncResult;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          result?.error == null
                              ? '${result?.successfulOperations ?? 0} changes synchronized'
                              : 'Sync stopped: ${result!.error}',
                        ),
                      ),
                    );
                  },
            icon: provider.isSyncing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            label: Text(provider.isSyncing ? 'Syncing...' : 'Sync now'),
          ),
          const SizedBox(height: 28),
          const Text('Recent Local Changes', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          if (provider.changes.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.history),
                title: Text('No local changes yet'),
                subtitle: Text('Changes made offline will appear here.'),
              ),
            )
          else
            ...provider.changes.reversed.take(10).map(
                  (change) =>                   _ChangeTile(
                    change: change,
                    noteTitle: _noteTitle(provider, change.recordId),
                  ),
                ),
          const SizedBox(height: 24),
          const Text('Recent activity', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
              title: const Text('1 conflict needs review'),
              subtitle: const Text('Project kickoff notes'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ConflictScreen()),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const _ActivityTile(icon: Icons.check_circle, color: Color(0xFF059669), title: 'Notes synchronized', detail: 'Today, 10:42 AM'),
          const _ActivityTile(icon: Icons.check_circle, color: Color(0xFF059669), title: 'Notes synchronized', detail: 'Yesterday, 6:18 PM'),
          const _ActivityTile(icon: Icons.info_outline, color: Colors.orange, title: 'Sync pending', detail: 'Yesterday, 3:05 PM'),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) => time.toLocal().toString().split('.').first;

  Widget _statCard(IconData icon, String label, String value, Color color) {
    return SizedBox(
      width: 170,
      height: 145,
      child: SyncStatusCard(icon: icon, label: label, value: value, color: color),
    );
  }

  String? _noteTitle(NoteProvider provider, String recordId) {
    for (final note in provider.notes) {
      if (note.id == recordId) return note.title;
    }
    return null;
  }
}

class _ChangeTile extends StatelessWidget {
  const _ChangeTile({required this.change, this.noteTitle});

  final ChangeLog change;
  final String? noteTitle;

  @override
  Widget build(BuildContext context) {
    final isSynced = change.synced;
    final color = isSynced ? const Color(0xFF059669) : Colors.orange.shade700;
    final title = noteTitle == null || noteTitle!.isEmpty
        ? change.recordId
        : noteTitle!;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(_operationIcon(change.operation), color: color),
        title: Text('${change.operation} - $title'),
        subtitle: Text('${change.timestamp.toIso8601String()}  |  v${change.version}'),
        trailing: Text(
          isSynced ? 'Synced' : 'Pending',
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  IconData _operationIcon(String operation) {
    switch (operation) {
      case 'CREATE':
        return Icons.add_circle_outline;
      case 'UPDATE':
        return Icons.edit_outlined;
      case 'DELETE':
        return Icons.delete_outline;
      default:
        return Icons.history;
    }
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.icon, required this.color, required this.title, required this.detail});

  final IconData icon;
  final Color color;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(detail),
    );
  }
}
