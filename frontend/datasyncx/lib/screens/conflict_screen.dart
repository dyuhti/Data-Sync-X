import 'package:flutter/material.dart';

class ConflictScreen extends StatelessWidget {
  const ConflictScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review conflict')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
                const SizedBox(width: 12),
                const Expanded(child: Text('A conflict was detected for this note.', style: TextStyle(fontWeight: FontWeight.w700))),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Record name', style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          const Text('Project kickoff notes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 22),
          _versionCard('My version', 'Updated today at 10:38 AM', 'Outline the sprint goals and assign owners to each task.', Colors.blue),
          const SizedBox(height: 12),
          _versionCard('Server version', 'Updated today at 10:40 AM', 'Outline the first sprint goals and align with the team.', Colors.deepPurple),
          const SizedBox(height: 28),
          const Text('Choose a resolution', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          _resolutionButton(context, 'Last-Writer-Wins', 'Use the most recently updated version', Icons.history),
          _resolutionButton(context, 'Field-Level Merge', 'Combine non-conflicting fields', Icons.merge_type),
          _resolutionButton(context, 'Manual Review', 'Choose which version to keep', Icons.rate_review_outlined),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _showManualOptions(context),
            icon: const Icon(Icons.edit_note),
            label: const Text('Manual review options'),
          ),
        ],
      ),
    );
  }

  Widget _versionCard(String title, String detail, String content, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(detail, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
              child: Text(content, style: const TextStyle(height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resolutionButton(BuildContext context, String title, String detail, IconData icon) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(detail),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$title selected (mock action)'))),
    );
  }

  void _showManualOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            const ListTile(title: Text('Manual review', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            ListTile(leading: const Icon(Icons.person_outline), title: const Text('Keep my version'), onTap: () => Navigator.pop(context)),
            ListTile(leading: const Icon(Icons.cloud_outlined), title: const Text('Keep server version'), onTap: () => Navigator.pop(context)),
          ],
        ),
      ),
    );
  }
}
