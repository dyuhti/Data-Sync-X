import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/conflict.dart';
import '../providers/note_provider.dart';
import '../theme/app_theme.dart';

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

class _ConflictDetail extends StatefulWidget {
  const _ConflictDetail({required this.conflict});

  final Conflict conflict;

  @override
  State<_ConflictDetail> createState() => _ConflictDetailState();
}

class _ConflictDetailState extends State<_ConflictDetail> {
  final _mergeFormKey = GlobalKey<FormState>();
  late final TextEditingController _mergeTitleController;
  late final TextEditingController _mergeContentController;
  bool _isResolving = false;
  bool _showMergeEditor = false;

  Conflict get conflict => widget.conflict;

  @override
  void initState() {
    super.initState();
    _mergeTitleController = TextEditingController(
      text:
          _payloadString(conflict.localPayload, 'title') ??
          _payloadString(conflict.remotePayload, 'title') ??
          '',
    );
    _mergeContentController = TextEditingController(
      text: _payloadString(conflict.localPayload, 'content') ?? '',
    );
  }

  @override
  void dispose() {
    _mergeTitleController.dispose();
    _mergeContentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title =
        _payloadString(conflict.localPayload, 'title') ??
        _payloadString(conflict.remotePayload, 'title') ??
        conflict.recordId;
    return Scaffold(
      appBar: AppBar(title: const Text('Review conflict')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _warningCard(),
              const SizedBox(height: 20),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Detected ${_formatDateTime(conflict.detectedAt)}',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              _metadataCard(),
              const SizedBox(height: 16),
              _snapshotCard(
                heading: 'Local version',
                version: conflict.localVersion,
                payload: conflict.localPayload,
                color: AppTheme.emerald,
              ),
              const SizedBox(height: 12),
              _snapshotCard(
                heading: 'Remote version',
                version: conflict.remoteVersion,
                payload: conflict.remotePayload,
                color: AppTheme.darkGreen,
              ),
              const SizedBox(height: 20),
              _resolutionActions(),
              if (_showMergeEditor) ...[
                const SizedBox(height: 16),
                _mergeEditor(),
              ],
              const SizedBox(height: 24),
            ],
          ),
          if (_isResolving)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _warningCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Choose which version to keep, or combine both snapshots '
              'manually before saving.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
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
          children: [
            _metadataRow('Conflict type', conflict.conflictType.value),
            _metadataRow('Operation', conflict.operation),
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

  Widget _snapshotCard({
    required String heading,
    required int? version,
    required Map<String, dynamic> payload,
    required Color color,
  }) {
    final isDeleted = payload['is_deleted'] == true;
    final content = _payloadString(payload, 'content') ?? '';
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
            if (isDeleted) ...[
              const SizedBox(height: 8),
              Chip(
                avatar: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Deleted'),
                backgroundColor: Colors.red.shade50,
                side: BorderSide.none,
              ),
            ],
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
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

  Widget _resolutionActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const ValueKey('keep-local-button'),
          onPressed: _isResolving ? null : _confirmKeepLocal,
          icon: const Icon(Icons.upload_rounded),
          label: const Text('Keep local'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const ValueKey('keep-server-button'),
          onPressed: _isResolving ? null : _confirmKeepServer,
          icon: const Icon(Icons.download_rounded),
          label: const Text('Keep server'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const ValueKey('manual-merge-button'),
          onPressed: _isResolving
              ? null
              : () => setState(() => _showMergeEditor = !_showMergeEditor),
          icon: const Icon(Icons.merge_type),
          label: Text(_showMergeEditor ? 'Hide merge editor' : 'Manual merge'),
        ),
      ],
    );
  }

  Widget _mergeEditor() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _mergeFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Create merged version',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Edit a new copy using either snapshot as a reference. '
                'Neither snapshot will be changed until you save.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('merge-title-field'),
                controller: _mergeTitleController,
                decoration: const InputDecoration(labelText: 'Merged title'),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('merge-content-field'),
                controller: _mergeContentController,
                minLines: 5,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Merged content',
                  alignLabelWithHint: true,
                ),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('save-merged-button'),
                onPressed: _isResolving ? null : _saveMerge,
                icon: const Icon(Icons.check),
                label: const Text('Save merged version'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required';
    }
    return null;
  }

  Future<void> _confirmKeepLocal() async {
    final confirmed = await _confirm(
      title: 'Keep local version?',
      message:
          'Your local content will replace the remote version after '
          'the next synchronization.',
      confirmLabel: 'Keep local',
    );
    if (confirmed == true) {
      await _resolve(
        () => context.read<NoteProvider>().keepLocal(conflict.conflictId),
      );
    }
  }

  Future<void> _confirmKeepServer() async {
    final confirmed = await _confirm(
      title: 'Keep server version?',
      message:
          'Local pending changes for this note will be superseded and '
          'the server snapshot will remain.',
      confirmLabel: 'Keep server',
    );
    if (confirmed == true) {
      await _resolve(
        () => context.read<NoteProvider>().keepServer(conflict.conflictId),
      );
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _saveMerge() async {
    if (!_mergeFormKey.currentState!.validate()) return;
    await _resolve(
      () => context.read<NoteProvider>().manualMerge(conflict.conflictId, {
        'id': conflict.recordId,
        'title': _mergeTitleController.text.trim(),
        'content': _mergeContentController.text.trim(),
        'is_deleted': false,
      }),
    );
  }

  Future<void> _resolve(
    Future<ConflictResolutionResult> Function() resolution,
  ) async {
    if (_isResolving) return;
    setState(() => _isResolving = true);
    try {
      await resolution();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conflict resolved successfully.')),
      );
      Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to resolve conflict: $error')),
      );
    } finally {
      if (mounted) setState(() => _isResolving = false);
    }
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
            Icon(Icons.check_circle_outline, size: 56, color: AppTheme.emerald),
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
