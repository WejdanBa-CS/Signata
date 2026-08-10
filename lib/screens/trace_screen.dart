import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/auth.dart';
import '../core/claim_crypto.dart';
import '../core/claim_registry.dart';
import '../core/claim_status_ui.dart';
import '../core/share_ingress.dart';
import '../core/share_utils.dart';
import '../core/social_platforms.dart';
import '../core/social_protect.dart';
import '../core/trace_models.dart';
import '../core/trace_store.dart';
import '../core/url_tracer.dart';
import '../core/usage_entitlements.dart';
import '../theme.dart';
import '../widgets/em_widgets.dart';
import '../widgets/usage_paywall.dart';

class TraceScreen extends StatefulWidget {
  const TraceScreen({
    super.key,
    this.initialSharedFiles = const [],
  });

  final List<SharedIngressFile> initialSharedFiles;

  @override
  State<TraceScreen> createState() => _TraceScreenState();
}

class _TraceScreenState extends State<TraceScreen>
    with SingleTickerProviderStateMixin {
  final _urlController = TextEditingController();
  late final AnimationController _radar;

  bool _busy = false;
  bool _watchAfterScan = true;
  String? _error;
  String? _status;
  TraceScanResult? _lastResult;
  SocialPlatformInfo? _selectedPlatform = SocialPlatformInfo.instagram;
  List<SocialProtectItem> _protected = const [];
  List<PublishedClaim> _claims = const [];
  List<WatchTarget> _watch = const [];
  List<TraceSighting> _sightings = const [];

  @override
  void initState() {
    super.initState();
    _radar = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _reload();
    if (widget.initialSharedFiles.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ingestShared(widget.initialSharedFiles);
      });
    }
  }

  @override
  void dispose() {
    _radar.dispose();
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
    final allowed = await ensureUsage(context, UsageKind.trace);
    if (!allowed || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Sweeping the open web…';
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
      setState(() {
        _lastResult = result;
        _status = null;
        final platform = SocialPlatformInfo.fromUrl(target);
        if (platform != null) _selectedPlatform = platform;
      });
      await _reload();
    } catch (error) {
      if (!mounted) return;
      setState(() =>
          _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  Future<void> _rescanAll() async {
    final allowed = await ensureUsage(context, UsageKind.trace);
    if (!allowed || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Rescanning watchlist…';
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
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  Future<void> _ingestShared(List<SharedIngressFile> files) async {
    final urls = files
        .where((f) => f.text != null && f.text!.startsWith('http'))
        .map((f) => f.text!.trim())
        .toList();
    if (urls.isNotEmpty) {
      _urlController.text = urls.first;
      final platform = SocialPlatformInfo.fromUrl(urls.first);
      if (platform != null) {
        setState(() => _selectedPlatform = platform);
      }
      await _scan(url: urls.first);
      return;
    }

    final media = files.where((f) => f.path.isNotEmpty).toList();
    if (media.isEmpty) return;
    await _protectPaths(media.map((f) => f.path).toList());
  }

  Future<void> _protectFromPicker() async {
    final allowed = await ensureUsage(context, UsageKind.protect);
    if (!allowed || !mounted) return;
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'png',
        'jpg',
        'jpeg',
        'webp',
        'mp4',
        'mov',
        'm4v',
        'wav',
      ],
    );
    if (picked == null || picked.files.isEmpty) return;

    final files = <({String name, Uint8List bytes})>[];
    for (final file in picked.files) {
      final bytes = await file.readAsBytes();
      files.add((name: file.name, bytes: bytes));
    }
    await _protectFiles(files);
  }

  Future<void> _protectPaths(List<String> paths) async {
    final allowed = await ensureUsage(context, UsageKind.protect);
    if (!allowed || !mounted) return;
    final files = <({String name, Uint8List bytes})>[];
    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) continue;
      files.add((
        name: path.split(Platform.pathSeparator).last,
        bytes: await file.readAsBytes(),
      ));
    }
    if (files.isEmpty) return;
    await _protectFiles(files);
  }

  Future<void> _protectFiles(
    List<({String name, Uint8List bytes})> files,
  ) async {
    final owner = AuthService.instance.user?.displayName.trim();
    if (owner == null || owner.isEmpty) {
      setState(() => _error = 'Sign in with a display name before protecting.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Fingerprinting ${files.length} file'
          '${files.length == 1 ? '' : 's'} for '
          '${_selectedPlatform?.label ?? 'social'}…';
      _protected = const [];
    });
    try {
      final items = await SocialProtectService.instance.protectMany(
        files: files,
        owner: owner,
      );
      if (!mounted) return;
      setState(() {
        _protected = items;
        _status = null;
      });
      await _reload();
    } catch (error) {
      if (!mounted) return;
      setState(() =>
          _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  Future<void> _shareProtected() async {
    final platform = _selectedPlatform;
    if (platform == null || _protected.isEmpty) return;
    await shareProtectedToSocial(
      platform: platform,
      items: _protected,
    );
  }

  Future<void> _openPlatform() async {
    final platform = _selectedPlatform;
    if (platform == null) return;
    final ok = await platform.openApp();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open ${platform.label}.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final platform = _selectedPlatform;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: _TraceHero(
              radar: _radar,
              busy: _busy,
              foundCount: _sightings.where((s) => s.found).length,
              watchCount: _watch.length,
              claimCount: _claims.length,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trace the signal',
                  style: theme.textTheme.displayMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Fingerprint media for Instagram, TikTok, and X — then scan public links for your claim.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: EmColors.mutedForeground,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
            child: _PlatformSelector(
              selected: _selectedPlatform,
              onSelected: (value) => setState(() => _selectedPlatform = value),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: EmCard(
              glow: _busy,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      MonoLabel(
                        platform == null
                            ? 'Scan any URL'
                            : 'Scan on ${platform.label}',
                      ),
                      const Spacer(),
                      if (platform != null)
                        TextButton(
                          onPressed: _busy ? null : _openPlatform,
                          child: Text('Open ${platform.shortLabel}'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const UsageStatusBanner(kind: UsageKind.trace),
                  TextField(
                    controller: _urlController,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _busy ? null : _scan(),
                    decoration: InputDecoration(
                      hintText: platform == null
                          ? 'https://cdn.example.com/photo.png'
                          : 'Paste a ${platform.label} post or media URL',
                      prefixIcon: const Icon(Icons.link_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _watchAfterScan,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _watchAfterScan = v),
                    title: const Text('Keep on radar'),
                    subtitle: const Text(
                      'Re-check this link later for your fingerprint.',
                      style: TextStyle(
                          fontSize: 12, color: EmColors.mutedForeground),
                    ),
                  ),
                  const SizedBox(height: 6),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _scan(),
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.radar, size: 18),
                    label: Text(_busy ? 'Scanning…' : 'Scan link'),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: EmCard(
              borderColor: Color(platform?.accent ?? 0xFF57D9EC)
                  .withValues(alpha: 0.45),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MonoLabel(
                    platform == null
                        ? 'Protect & post'
                        : 'Protect for ${platform.label}',
                    color: Color(platform?.accent ?? 0xFF57D9EC),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    platform?.hint ??
                        'Import images or videos, fingerprint all of them, then share into the social app.',
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: EmColors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _busy ? null : _protectFromPicker,
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: const Text('Fingerprint media'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy || _protected.isEmpty
                            ? null
                            : _shareProtected,
                        icon: const Icon(Icons.ios_share, size: 18),
                        label: Text(
                          _protected.isEmpty
                              ? 'Share to app'
                              : 'Share ${_protected.length} to ${platform?.shortLabel ?? 'app'}',
                        ),
                      ),
                    ],
                  ),
                  if (_protected.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    ..._protected.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(
                              item.medium == TraceMedium.video
                                  ? Icons.movie_outlined
                                  : item.medium == TraceMedium.audio
                                      ? Icons.graphic_eq
                                      : Icons.image_outlined,
                              size: 18,
                              color: EmColors.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                item.fileName,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              item.reference.length > 10
                                  ? item.reference.substring(0, 10)
                                  : item.reference,
                              style: emMonoLabel(size: 9),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Tip: In Instagram, TikTok, or X use Share → Signata to send media or a post link straight here.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: EmColors.mutedForeground,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_status != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _PulseStatus(text: _status!),
            ),
          ),
        if (_error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: StatusBanner(
                ok: false,
                title: 'Trace interrupted',
                subtitle: _error!,
              ),
            ),
          ),
        if (_lastResult != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _ResultCard(result: _lastResult!),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('RADAR WATCHLIST', style: emMonoLabel(size: 10)),
                ),
                TextButton(
                  onPressed: _busy || _watch.isEmpty ? null : _rescanAll,
                  child: const Text('Rescan all'),
                ),
              ],
            ),
          ),
        ),
        if (_watch.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'No links on radar yet. Scan a social or media URL with “Keep on radar”.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: EmColors.mutedForeground,
                ),
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: _watch.length,
            itemBuilder: (context, index) {
              final w = _watch[index];
              final social = SocialPlatformInfo.fromUrl(w.url);
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: _WatchTile(
                  target: w,
                  platform: social,
                  busy: _busy,
                  onScan: () {
                    _urlController.text = w.url;
                    _scan(url: w.url);
                  },
                  onRemove: () async {
                    await TraceStore.instance.removeWatchTarget(w.id);
                    await _reload();
                  },
                ),
              );
            },
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Text('PUBLISHED CLAIMS', style: emMonoLabel(size: 10)),
          ),
        ),
        if (_claims.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Protect media above (or in any tool) to publish claims Trace can match online.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: EmColors.mutedForeground,
                ),
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: math.min(_claims.length, 20),
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: _ClaimTile(claim: _claims[index]),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Text('SIGHTING TIMELINE', style: emMonoLabel(size: 10)),
          ),
        ),
        if (_sightings.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              child: Text(
                'Sightings appear as a timeline whenever a scan finds — or misses — a fingerprint.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: EmColors.mutedForeground,
                ),
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: math.min(_sightings.length, 25),
            itemBuilder: (context, index) => Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                index == math.min(_sightings.length, 25) - 1 ? 40 : 0,
              ),
              child: _SightingTile(
                sighting: _sightings[index],
                isFirst: index == 0,
                isLast: index == math.min(_sightings.length, 25) - 1,
              ),
            ),
          ),
      ],
    );
  }
}

class _TraceHero extends StatelessWidget {
  const _TraceHero({
    required this.radar,
    required this.busy,
    required this.foundCount,
    required this.watchCount,
    required this.claimCount,
  });

  final AnimationController radar;
  final bool busy;
  final int foundCount;
  final int watchCount;
  final int claimCount;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: RadialGradient(
                  center: const Alignment(0, -0.2),
                  radius: 1.05,
                  colors: [
                    EmColors.primary.withValues(alpha: busy ? 0.28 : 0.16),
                    EmColors.accent.withValues(alpha: 0.08),
                    EmColors.background.withValues(alpha: 0.2),
                  ],
                ),
                border: Border.all(color: EmColors.border),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: radar,
            builder: (context, _) => CustomPaint(
              size: const Size(180, 180),
              painter: _RadarPainter(
                progress: radar.value,
                accent: busy ? EmColors.accent : EmColors.primary,
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 16,
            child: Row(
              children: [
                _StatChip(label: 'Found', value: '$foundCount'),
                const SizedBox(width: 8),
                _StatChip(label: 'Watching', value: '$watchCount'),
                const SizedBox(width: 8),
                _StatChip(label: 'Claims', value: '$claimCount'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: EmColors.background.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: EmColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: emMonoLabel(color: EmColors.mutedForeground, size: 8)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: EmColors.foreground)),
          ],
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter({required this.progress, required this.accent});

  final double progress;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.42;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = EmColors.foreground.withValues(alpha: 0.12);

    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(center, radius * (i / 3), ring);
    }
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      ring,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      ring,
    );

    final sweep = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi / 2,
        colors: [
          accent.withValues(alpha: 0.0),
          accent.withValues(alpha: 0.55),
        ],
        transform: GradientRotation(progress * math.pi * 2),
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, sweep..style = PaintingStyle.fill);

    final beam = Paint()
      ..color = accent
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final angle = progress * math.pi * 2;
    canvas.drawLine(
      center,
      Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      ),
      beam,
    );

    canvas.drawCircle(
      center,
      5,
      Paint()..color = accent,
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.accent != accent;
}

class _PlatformSelector extends StatelessWidget {
  const _PlatformSelector({
    required this.selected,
    required this.onSelected,
  });

  final SocialPlatformInfo? selected;
  final ValueChanged<SocialPlatformInfo> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final platform in SocialPlatformInfo.all) ...[
          if (platform != SocialPlatformInfo.all.first) const SizedBox(width: 10),
          Expanded(
            child: _PlatformCard(
              platform: platform,
              selected: selected?.id == platform.id,
              onTap: () => onSelected(platform),
            ),
          ),
        ],
      ],
    );
  }
}

class _PlatformCard extends StatelessWidget {
  const _PlatformCard({
    required this.platform,
    required this.selected,
    required this.onTap,
  });

  final SocialPlatformInfo platform;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon => switch (platform.id) {
        SocialPlatform.instagram => Icons.photo_camera_outlined,
        SocialPlatform.tiktok => Icons.music_note_outlined,
        SocialPlatform.x => Icons.tag_outlined,
        SocialPlatform.other => Icons.public,
      };

  @override
  Widget build(BuildContext context) {
    final accent = Color(platform.accent);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.14)
                : EmColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.7)
                  : EmColors.border,
            ),
          ),
          child: Column(
            children: [
              Icon(_icon,
                  color: selected ? accent : EmColors.mutedForeground),
              const SizedBox(height: 8),
              Text(
                platform.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? EmColors.foreground : EmColors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PulseStatus extends StatefulWidget {
  const _PulseStatus({required this.text});

  final String text;

  @override
  State<_PulseStatus> createState() => _PulseStatusState();
}

class _PulseStatusState extends State<_PulseStatus>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: EmColors.primary
                  .withValues(alpha: 0.25 + _controller.value * 0.35),
            ),
            color: EmColors.primary.withValues(alpha: 0.08),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: EmColors.primary
                      .withValues(alpha: 0.55 + _controller.value * 0.45),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.text,
                  style: const TextStyle(
                    fontSize: 13,
                    color: EmColors.foreground,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WatchTile extends StatelessWidget {
  const _WatchTile({
    required this.target,
    required this.platform,
    required this.busy,
    required this.onScan,
    required this.onRemove,
  });

  final WatchTarget target;
  final SocialPlatformInfo? platform;
  final bool busy;
  final VoidCallback onScan;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final accent = Color(platform?.accent ?? 0xFF57D9EC);
    return EmCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.45),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  target.label ?? platform?.label ?? 'Watch target',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            target.url,
            style: const TextStyle(
              fontSize: 12,
              color: EmColors.mutedForeground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            target.lastScannedAt == null
                ? 'Awaiting first sweep'
                : 'Last sweep · ${_fmt(target.lastScannedAt!)}'
                    '${target.lastReference == null ? '' : ' · ${target.lastReference}'}',
            style: emMonoLabel(color: EmColors.mutedForeground, size: 9),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton(
                onPressed: busy ? null : onScan,
                child: const Text('Scan'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onRemove,
                child: const Text('Remove'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClaimTile extends StatelessWidget {
  const _ClaimTile({required this.claim});

  final PublishedClaim claim;

  @override
  Widget build(BuildContext context) {
    return EmCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${claim.medium.wire.toUpperCase()} · ${claim.subject}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(claim.owner,
              style: const TextStyle(
                  fontSize: 13, color: EmColors.mutedForeground)),
          const SizedBox(height: 8),
          SelectableText(claim.reference, style: emMonoLabel(size: 10)),
          const SizedBox(height: 6),
          Text(
            claim.remoteSynced
                ? 'Synced to remote registry'
                : 'Stored on this device'
                    '${ClaimRegistry.hasRemote ? ' · remote sync pending/failed' : ''}',
            style: emMonoLabel(color: EmColors.mutedForeground, size: 9),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: claim.reference));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Fingerprint copied')),
                );
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy fingerprint'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SightingTile extends StatelessWidget {
  const _SightingTile({
    required this.sighting,
    required this.isFirst,
    required this.isLast,
  });

  final TraceSighting sighting;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = sighting.found ? EmColors.accent : EmColors.mutedForeground;
    final social = SocialPlatformInfo.fromUrl(sighting.url);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 22,
            child: Column(
              children: [
                Container(
                  width: 2,
                  height: isFirst ? 8 : 0,
                  color: Colors.transparent,
                ),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast
                        ? Colors.transparent
                        : EmColors.border,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: EmCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            sighting.found
                                ? (sighting.matchedPublishedClaimId != null
                                    ? 'Matched your claim'
                                    : 'Fingerprint found')
                                : 'No fingerprint',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: sighting.found
                                  ? EmColors.accent
                                  : EmColors.foreground,
                            ),
                          ),
                        ),
                        if (social != null)
                          Text(
                            social.shortLabel,
                            style: emMonoLabel(
                              color: Color(social.accent),
                              size: 9,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sighting.url,
                      style: const TextStyle(
                        fontSize: 12,
                        color: EmColors.mutedForeground,
                      ),
                    ),
                    if (sighting.owner != null) ...[
                      const SizedBox(height: 6),
                      Text('${sighting.owner} · ${sighting.subject ?? sighting.medium.wire}'),
                    ],
                    if (sighting.reference != null) ...[
                      const SizedBox(height: 6),
                      Text(sighting.reference!, style: emMonoLabel(size: 9)),
                    ],
                    if (sighting.error != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        sighting.error!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: EmColors.destructive,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      _fmt(sighting.at),
                      style: emMonoLabel(
                        color: EmColors.mutedForeground,
                        size: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
    final social = SocialPlatformInfo.fromUrl(s.url);
    return EmCard(
      glow: s.found,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (social != null) ...[
            MonoLabel('Hit on ${social.label}', color: Color(social.accent)),
            const SizedBox(height: 10),
          ],
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

String _fmt(DateTime at) {
  final local = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
