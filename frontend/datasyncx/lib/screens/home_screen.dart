import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../providers/note_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/connectivity_badge.dart';
import '../widgets/note_card.dart';
import 'note_editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NoteProvider>();
    final notes = provider.notes.where((note) {
      final query = _query.toLowerCase();
      return note.title.toLowerCase().contains(query) ||
          note.content.toLowerCase().contains(query);
    }).toList();

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(child: _header(context)),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            sliver: SliverToBoxAdapter(child: _overview(provider)),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            sliver: SliverToBoxAdapter(
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  hintText: 'Search your notes',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: notes.isEmpty
                ? const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Center(child: Text('No notes found')),
                    ),
                  )
                : SliverList.builder(
                    itemCount: notes.length,
                    itemBuilder: (_, index) => NoteCard(
                      note: notes[index],
                      onTap: () => _openEditor(context, notes[index]),
                    ),
                  ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 90)),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Data Sync X', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Welcome back, keep creating.', style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ),
        const ConnectivityBadge(),
      ],
    );
  }

  Widget _overview(NoteProvider provider) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.darkGreen,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          _stat('Notes', '${provider.notes.length}'),
          _divider(),
          _stat('Pending', '${provider.pendingCount}'),
          _divider(),
          _stat('Last sync', '10:42 AM'),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _divider() => Container(height: 36, width: 1, color: Colors.white24);

  Future<void> _openEditor(BuildContext context, Note note) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => NoteEditorScreen(note: note)),
    );
  }
}
