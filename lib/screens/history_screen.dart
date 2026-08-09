import 'package:flutter/material.dart';

import '../core/history.dart';
import '../theme.dart';
import '../widgets/em_widgets.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  List<HistoryEntry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final entries = await HistoryStore.load();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: EmColors.card,
        title: const Text('Clear history?'),
        content: const Text(
            'This removes all locally stored verification records. Watermarked files are not affected.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear',
                style: TextStyle(color: EmColors.destructive)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await HistoryStore.clear();
    await refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: EmColors.primary),
      );
    }

    if (_entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const EmLogo(size: 44, showWordmark: false),
              const SizedBox(height: 20),
              Text('No verifications yet',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'Every fingerprint you embed or verify is recorded here — on this device only.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: EmColors.mutedForeground),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      children: [
        Row(
          children: [
            const Expanded(
              child: SectionHeading(
                tag: 'On-device records',
                title: 'History',
              ),
            ),
            IconButton(
              onPressed: _clear,
              tooltip: 'Clear history',
              icon: const Icon(Icons.delete_outline,
                  color: EmColors.mutedForeground),
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (final entry in _entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: EmCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: (entry.verified
                              ? EmColors.accent
                              : EmColors.destructive)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      switch (entry.medium) {
                        'image' => Icons.image_outlined,
                        'audio' => Icons.graphic_eq,
                        'video' => Icons.movie_outlined,
                        _ => Icons.description_outlined,
                      },
                      size: 19,
                      color: entry.verified
                          ? EmColors.accent
                          : EmColors.destructive,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                              color: EmColors.foreground),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${entry.action == 'embed' ? 'Protected' : 'Verified'} · ${entry.owner}',
                          style: const TextStyle(
                              fontSize: 12,
                              color: EmColors.mutedForeground),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _shortRef(entry.reference),
                          style: emMono(
                              color: EmColors.mutedForeground, size: 10),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Icon(
                        entry.verified
                            ? Icons.verified_outlined
                            : Icons.error_outline,
                        size: 17,
                        color: entry.verified
                            ? EmColors.accent
                            : EmColors.destructive,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatDate(entry.at),
                        style: const TextStyle(
                            fontSize: 10.5,
                            color: EmColors.mutedForeground),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static String _shortRef(String ref) =>
      ref.length <= 20 ? ref : '${ref.substring(0, 20)}…';

  static String _formatDate(DateTime at) {
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year}\n${two(local.hour)}:${two(local.minute)}';
  }
}
