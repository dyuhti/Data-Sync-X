import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoSync = true;
  String _policy = 'Last-Writer-Wins';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text('Settings', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),
          const Text('Synchronization', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: _autoSync,
                  onChanged: (value) => setState(() => _autoSync = value),
                  title: const Text('Automatic synchronization'),
                  subtitle: const Text('Sync changes when a connection is available'),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Default conflict policy'),
                  subtitle: Text(_policy),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _selectPolicy,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('About', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: const [
                ListTile(
                  leading: Icon(Icons.sync_alt),
                  title: Text('About Data Sync X'),
                  subtitle: Text('Offline-first notes for every moment'),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Application version'),
                  trailing: Text('1.0.0', style: TextStyle(color: Colors.grey)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectPolicy() async {
    final policy = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: RadioGroup<String>(
          groupValue: _policy,
          onChanged: (value) {
            if (value != null) Navigator.pop(context, value);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Default conflict policy', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
              for (final option in ['Last-Writer-Wins', 'Field-Level Merge', 'Manual Review'])
                RadioListTile<String>(
                  value: option,
                  title: Text(option),
                ),
            ],
          ),
        ),
      ),
    );
    if (policy != null) setState(() => _policy = policy);
  }
}
