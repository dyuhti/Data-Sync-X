import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/note_provider.dart';
import '../widgets/connectivity_badge.dart';
import '../widgets/sync_status_card.dart';
import 'conflict_screen.dart';

class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pending = context.watch<NoteProvider>().pendingCount;
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
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('All systems operational', style: TextStyle(fontWeight: FontWeight.w700)),
                      SizedBox(height: 4),
                      Text('Last successful sync today at 10:42 AM', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 125,
            child: Row(
              children: [
                Expanded(child: SyncStatusCard(icon: Icons.pending_actions, label: 'Pending changes', value: '$pending', color: Colors.orange.shade700)),
                const SizedBox(width: 12),
                const Expanded(child: SyncStatusCard(icon: Icons.check_circle_outline, label: 'Synced records', value: '24', color: Color(0xFF059669))),
                const SizedBox(width: 12),
                Expanded(child: SyncStatusCard(icon: Icons.error_outline, label: 'Failed syncs', value: '0', color: Colors.red.shade600)),
              ],
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sync started (mock action)'))),
            icon: const Icon(Icons.sync),
            label: const Text('Sync now'),
          ),
          const SizedBox(height: 28),
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
