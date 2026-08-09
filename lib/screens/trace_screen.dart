import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/claim_crypto.dart';
import '../core/claim_registry.dart';
import '../core/claim_status_ui.dart';
import '../core/trace_models.dart';
import '../core/trace_store.dart';
import '../core/url_tracer.dart';
import '../theme.dart';
import '../widgets/em_widgets.dart';

class TraceScreen extends StatefulWidget {
  const TraceScreen({super.key});

  @override
  State<TraceScreen> createState() => _TraceScreenState();
}

class _TraceScreenState extends State<TraceScreen> {
  final _urlController = TextEditingController();
  bool _busy = false;
  bool _watchAfterScan = true;
  String? _error;
  TraceScanResult? _lastResult;
  List<PublishedClaim> _claims = const [];
  List<WatchTarget> _watch = const [];
  List<TraceSighting> _sightings = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final claims = await ClaimRegistry.instance.listLocal();
    final watch = await TraceStore.instance.listWatchTargets();
    final sightings = await TraceStore.instance.listSightings();
    if (!mounted) return;
    setState(() {
      _claims = claims;
      _watch = watch;
      _sightings = sightings;
    });
  }

  Future<void> _scan({String? url}) async {
    final target = (url ?? _urlController.text).trim();
    setState(() {
      _busy = true;
      _error = null;
      _lastResult = null;
    });
    try {
      final key = await AccountClaimKeys.current();
      final result = await UrlTracer.instance.scanUrl(
        target,
        claimKey: key,
        addToWatchlist: _watchAfterScan,
      );
      if (!mounted) return;
      setState(() => _lastResult = result);
      await _reload();
    } catch (error) {
      if (!mounted) return;
      setState(() =>
          _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rescanAll() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final key = await AccountClaimKeys.current();
      await UrlTracer.instance.scanWatchlist(claimKey: key);
      await _reload();
    } catch (error) {
      if (!mounted) return;
      setState(() =>
          _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final remote = ClaimRegistry.hasRemote;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      children: [
        SectionHeading(
          tag: 'Internet trace',
          title: 'Find Signata media on the web',
          desc: remote
              ? 'Paste a public media URL to download and scan it for a Signata fingerprint. Claims can sync to your registry at ${ClaimRegistry.remoteBaseUrl}.'
              : 'Paste a public media URL to download and scan it for a Signata fingerprint. Publish claims after protecting a file so sightings can match your catalog. Optional remote sync: set SIGNATA_REGISTRY_URL.',
        ),
        const SizedBox(height: 20),
        EmCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MonoLabel('Scan a public URL'),
              const SizedBox(height: 10),
              TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _busy ? null : _scan(),
                decoration: const InputDecoration(
                  hintText: 'https://example.com/photo.png',
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _watchAfterScan,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _watchAfterScan = v),
                title: const Text('Add to watchlist'),
                subtitle: const Text(
                  'Re-scan later to see if the fingerprint is still online.',
                  style: TextStyle(fontSize: 12, color: EmColors.mutedForeground),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy ? null : () => _scan(),
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.travel_explore, size: 18),
                label: Text(_busy ? 'Scanning…' : 'Scan URL'),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          StatusBanner(ok: false, title: 'Scan failed', subtitle: _error!),
        ],
        if (_lastResult != null) ...[
          const SizedBox(height: 16),
          _ResultCard(result: _lastResult!),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text('WATCHLIST', style: emMonoLabel(size: 10)),
            ),
            TextButton(
              onPressed: _busy || _watch.isEmpty ? null : _rescanAll,
              child: const Text('Rescan all'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_watch.isEmpty)
          const Text(
            'No watched URLs yet. Scan a link with “Add to watchlist” enabled.',
            style: TextStyle(fontSize: 13, color: EmColors.mutedForeground),
          )
        else
          ..._watch.map((w) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: EmCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(w.label ?? w.url,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      if (w.label != null) ...[
                        const SizedBox(height: 4),
                        Text(w.url,
                            style: const TextStyle(
                                fontSize: 12,
                                color: EmColors.mutedForeground)),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        w.lastScannedAt == null
                            ? 'Not scanned yet'
                            : 'Last scan · ${_fmt(w.lastScannedAt!)}'
                                '${w.lastReference == null ? '' : ' · ${w.lastReference}'}',
                        style: emMonoLabel(
                            color: EmColors.mutedForeground, size: 9),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    _urlController.text = w.url;
                                    _scan(url: w.url);
                                  },
                            child: const Text('Scan'),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () async {
                              await TraceStore.instance.removeWatchTarget(w.id);
                              await _reload();
                            },
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )),
        const SizedBox(height: 24),
        Text('MY PUBLISHED CLAIMS', style: emMonoLabel(size: 10)),
        const SizedBox(height: 8),
        if (_claims.isEmpty)
          const Text(
            'After you protect a file, use “Publish for web tracing” so online scans can match it to you.',
            style: TextStyle(fontSize: 13, color: EmColors.mutedForeground),
          )
        else
          ..._claims.take(20).map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: EmCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${c.medium.wire.toUpperCase()} · ${c.subject}',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(c.owner,
                          style: const TextStyle(
                              fontSize: 13, color: EmColors.mutedForeground)),
                      const SizedBox(height: 8),
                      SelectableText(
                        c.reference,
                        style: emMonoLabel(size: 10),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        c.remoteSynced
                            ? 'Synced to remote registry'
                            : 'Stored on this device'
                                '${ClaimRegistry.hasRemote ? ' · remote sync pending/failed' : ''}',
                        style: emMonoLabel(
                            color: EmColors.mutedForeground, size: 9),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                                ClipboardData(text: c.reference));
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Fingerprint copied')),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy fingerprint'),
                        ),
                      ),
                    ],
                  ),
                ),
              )),
        const SizedBox(height: 24),
        Text('RECENT SIGHTINGS', style: emMonoLabel(size: 10)),
        const SizedBox(height: 8),
        if (_sightings.isEmpty)
          const Text(
            'Sightings appear here whenever a URL scan finds (or misses) a fingerprint.',
            style: TextStyle(fontSize: 13, color: EmColors.mutedForeground),
          )
        else
          ..._sightings.take(25).map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: EmCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.found
                            ? (s.matchedPublishedClaimId != null
                                ? 'Matched your published claim'
                                : 'Fingerprint found')
                            : 'No fingerprint',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: s.found ? EmColors.accent : EmColors.foreground,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(s.url,
                          style: const TextStyle(
                              fontSize: 12, color: EmColors.mutedForeground)),
                      if (s.owner != null) ...[
                        const SizedBox(height: 6),
                        Text('${s.owner} · ${s.subject ?? s.medium.wire}'),
                      ],
                      if (s.reference != null) ...[
                        const SizedBox(height: 6),
                        Text(s.reference!, style: emMonoLabel(size: 9)),
                      ],
                      if (s.error != null) ...[
                        const SizedBox(height: 6),
                        Text(s.error!,
                            style: const TextStyle(
                                fontSize: 12, color: EmColors.destructive)),
                      ],
                      const SizedBox(height: 6),
                      Text(_fmt(s.at),
                          style: emMonoLabel(
                              color: EmColors.mutedForeground, size: 9)),
                    ],
                  ),
                ),
              )),
      ],
    );
  }

  static String _fmt(DateTime at) {
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final TraceScanResult result;

  @override
  Widget build(BuildContext context) {
    final s = result.sighting;
    final banner = s.error != null
        ? (ok: false, title: 'Could not scan URL', subtitle: s.error!)
        : claimBanner(s.claimStatus);
    return EmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusBanner(
            ok: banner.ok,
            title: banner.title,
            subtitle: result.matchedClaim != null
                ? '${banner.subtitle} Matched published claim “${result.matchedClaim!.subject}”.'
                : banner.subtitle,
          ),
          const SizedBox(height: 14),
          DetailList(rows: [
            DetailRow('URL', s.url),
            DetailRow('Medium', s.medium.wire),
            DetailRow('Owner', s.owner ?? '—'),
            DetailRow('Subject', s.subject ?? '—'),
            DetailRow('Fingerprint', s.reference ?? '—', mono: true),
            DetailRow(
              'Catalog match',
              result.matchedClaim == null ? 'none' : 'your claim',
            ),
          ]),
        ],
      ),
    );
  }
}
