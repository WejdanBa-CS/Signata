import 'package:flutter/material.dart';

import '../core/onboarding.dart';
import '../theme.dart';
import '../widgets/em_widgets.dart';
import 'tools_hub_screen.dart';

class _Feature {
  const _Feature(this.tag, this.title, this.desc, this.points, this.icon);

  final String tag;
  final String title;
  final String desc;
  final List<String> points;
  final IconData icon;
}

const _features = [
  _Feature(
    '01 / Visual',
    'Image Watermarking',
    'Hidden watermark embedding that survives compression, cropping, and color shifts. Encrypted ownership metadata lives inside the pixels — invisible to the eye, recoverable on demand.',
    [
      'Hidden watermark embedding',
      'Ownership verification',
      'Encrypted metadata',
      'Robustness against common modifications',
    ],
    Icons.image_outlined,
  ),
  _Feature(
    '02 / Audio',
    'Audio Watermarking',
    'Inaudible fingerprints woven into the signal spectrum. Persistent embedded identifiers that travel with your audio across re-encoding, streaming, and redistribution.',
    [
      'Inaudible audio fingerprints',
      'Persistent embedded signals',
      'Verification and extraction',
    ],
    Icons.graphic_eq,
  ),
  _Feature(
    '03 / Video',
    'Video Fingerprinting',
    'Structural ownership identifiers bound to MP4/MOV containers — proving provenance across shares without changing how the video plays.',
    [
      'Container structure profiling',
      'SHA-256 ownership identifiers',
      'On-device verification',
    ],
    Icons.movie_outlined,
  ),
  _Feature(
    '04 / Documents',
    'PDF Fingerprinting',
    'Hidden ownership identifiers embedded in document structure with protected metadata — proving provenance for documents without altering the reading experience.',
    [
      'Hidden ownership identifiers',
      'Metadata protection',
      'Structural fingerprinting',
    ],
    Icons.description_outlined,
  ),
];

const _steps = [
  (
    '01',
    'Protect',
    'Signata embeds a signed fingerprint into your media on this device — invisible, bound to your account key.'
  ),
  (
    '02',
    'Publish locally',
    'Claims stay on your phone (optional self-hosted registry later). No Signata cloud database is required.'
  ),
  (
    '03',
    'Trace & verify',
    'Scan a shared file or URL to recover the fingerprint and confirm it matches your Signata key.'
  ),
];

const _goals = [
  'Protect creators from unauthorized redistribution',
  'Preserve ownership signals across social recompression when possible',
  'Keep fingerprints verifiable entirely on-device',
  'Research robust watermark persistence techniques',
  'Explore anti-tampering and anti-removal methods',
];

const _tech = [
  'Flutter',
  'Dart',
  'HMAC-SHA256',
  'LSB / WAV stego',
  'On-device secure storage',
  'Android share intents',
];

const _milestones = [
  (
    'Shipped in app',
    true,
    'On-device creator suite',
    [
      'Image LSB watermarking',
      'Audio WAV watermarking',
      'Video + PDF structural fingerprints',
      'Trace radar + account-bound claims',
    ]
  ),
  (
    'In progress',
    true,
    'Social resilience & Trace',
    [
      'Share-intent first workflows',
      'Watchlist digests',
      'Clearer platform-strip messaging',
    ]
  ),
  (
    'Research roadmap',
    false,
    'Optional cloud later',
    [
      'Optional claim registry',
      'Cross-device sync (optional)',
      'Stronger anti-recompress marks',
    ]
  ),
];

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.onOpenTool,
    this.onOpenAccount,
    this.checklistNonce = 0,
  });

  final void Function(EmTool tool) onOpenTool;
  final VoidCallback? onOpenAccount;
  final int checklistNonce;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _Hero(onOpenTool: onOpenTool),
        _StarterChecklist(
          key: ValueKey('checklist-$checklistNonce'),
          onOpenTool: onOpenTool,
          onOpenAccount: onOpenAccount,
        ),
        const _StatsStrip(),
        const _SectionPadding(child: _Features()),
        _bandDecoration(const _HowItWorks()),
        const _SectionPadding(child: _Goals()),
        _bandDecoration(const _Architecture()),
        const _SectionPadding(child: _Technologies()),
        _bandDecoration(_Status(onOpenTool: onOpenTool)),
        const _Footer(),
      ],
    );
  }

  Widget _bandDecoration(Widget child) {
    return Container(
      decoration: const BoxDecoration(
        color: EmColors.surface,
        border: Border.symmetric(
          horizontal: BorderSide(color: EmColors.border),
        ),
      ),
      child: _SectionPadding(child: child),
    );
  }
}

class _StarterChecklist extends StatefulWidget {
  const _StarterChecklist({
    super.key,
    required this.onOpenTool,
    this.onOpenAccount,
  });

  final void Function(EmTool tool) onOpenTool;
  final VoidCallback? onOpenAccount;

  @override
  State<_StarterChecklist> createState() => _StarterChecklistState();
}

class _StarterChecklistState extends State<_StarterChecklist> {
  bool _loading = true;
  bool _show = false;
  bool _recovery = false;
  bool _protected = false;
  bool _traced = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final show = await OnboardingFlags.instance.shouldShowChecklist();
    final progress = await OnboardingFlags.instance.checklistProgress();
    if (!mounted) return;
    setState(() {
      _show = show;
      _recovery = progress.recovery;
      _protected = progress.protected;
      _traced = progress.traced;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || !_show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: EmCard(
        borderColor: EmColors.accent.withValues(alpha: 0.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: MonoLabel('Starter checklist', color: EmColors.accent),
                ),
                TextButton(
                  onPressed: () async {
                    await OnboardingFlags.instance.dismissChecklist();
                    if (!mounted) return;
                    setState(() => _show = false);
                  },
                  child: const Text('Dismiss'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Three local steps to get value from Signata quickly:',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: EmColors.mutedForeground,
              ),
            ),
            const SizedBox(height: 12),
            _CheckRow(
              done: _recovery,
              label: 'Export a recovery kit',
              action: 'Account',
              onTap: widget.onOpenAccount,
            ),
            _CheckRow(
              done: _protected,
              label: 'Protect one file',
              action: 'Image tool',
              onTap: () => widget.onOpenTool(EmTool.image),
            ),
            _CheckRow(
              done: _traced,
              label: 'Check a file in Trace',
              action: 'Trace',
              onTap: () => widget.onOpenTool(EmTool.trace),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.done,
    required this.label,
    required this.action,
    this.onTap,
  });

  final bool done;
  final String label;
  final String action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: done ? EmColors.accent : EmColors.mutedForeground,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                decoration: done ? TextDecoration.lineThrough : null,
                color: done ? EmColors.mutedForeground : EmColors.foreground,
              ),
            ),
          ),
          if (!done && onTap != null)
            TextButton(onPressed: onTap, child: Text(action)),
        ],
      ),
    );
  }
}

class _SectionPadding extends StatelessWidget {
  const _SectionPadding({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 48),
      child: child,
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.onOpenTool});

  final void Function(EmTool) onOpenTool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        const GridBackdrop(spacing: 48, opacity: 0.05),
        Positioned(
          top: -140,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: EmColors.primary.withValues(alpha: 0.18),
                    blurRadius: 120,
                    spreadRadius: 40,
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 40, 20, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MonoLabel('Digital Watermarking Platform'),
              const SizedBox(height: 16),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Invisible ownership.\n'),
                    TextSpan(
                      text: 'Verifiable authenticity.',
                      style: TextStyle(color: theme.colorScheme.primary),
                    ),
                  ],
                ),
                style: theme.textTheme.displayLarge,
              ),
              const SizedBox(height: 18),
              Text(
                'Signata embeds hidden, encrypted fingerprints inside images, audio, and PDFs — preserving the original experience while letting creators prove ownership and authenticity of their work.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: EmColors.mutedForeground,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton(
                    onPressed: () => onOpenTool(EmTool.image),
                    child: const Text('Try the image tool'),
                  ),
                  OutlinedButton(
                    onPressed: () => onOpenTool(EmTool.audio),
                    child: const Text('Protect audio'),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  const _PulsingDot(),
                  const SizedBox(width: 8),
                  Text(
                    'Research & prototype phase',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: EmColors.mutedForeground),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              _HeroVisual(),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroVisual extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: EmColors.border),
            boxShadow: [
              BoxShadow(
                color: EmColors.primary.withValues(alpha: 0.3),
                blurRadius: 44,
                spreadRadius: -10,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Image.asset(
              'assets/hero_signal.png',
              fit: BoxFit.cover,
              width: double.infinity,
              height: 260,
            ),
          ),
        ),
        Positioned(
          bottom: -14,
          left: 14,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: EmColors.card.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: EmColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: EmColors.accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check,
                      size: 18, color: EmColors.accent),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MonoLabel('Verified', color: EmColors.accent),
                    const SizedBox(height: 2),
                    const Text(
                      'Ownership confirmed',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: EmColors.foreground),
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
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

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
        return SizedBox(
          width: 16,
          height: 16,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 8 + 8 * _controller.value,
                height: 8 + 8 * _controller.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: EmColors.accent
                      .withValues(alpha: 0.6 * (1 - _controller.value)),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: EmColors.accent,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip();

  static const _stats = [
    ('4', 'Media formats supported'),
    ('1', 'Fingerprint per asset'),
    ('0', 'Visible changes to content'),
    ('∞', 'Verifications per fingerprint'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: const BoxDecoration(
        color: EmColors.surface,
        border: Border.symmetric(
          horizontal: BorderSide(color: EmColors.border),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 2.1,
        children: [
          for (final (value, label) in _stats)
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value,
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(color: EmColors.primary)),
                const SizedBox(height: 6),
                Text(
                  label.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: emMonoLabel(
                      color: EmColors.mutedForeground, size: 9),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Features extends StatelessWidget {
  const _Features();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading(
          tag: 'Capabilities',
          title: 'One platform, four media formats',
          desc:
              'Signata protects digital content across the formats creators actually ship — without altering how it looks or sounds.',
        ),
        const SizedBox(height: 24),
        for (final f in _features)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: EmCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      MonoLabel(f.tag),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: EmColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child:
                            Icon(f.icon, color: EmColors.primary, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(f.title, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    f.desc,
                    style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.5,
                        color: EmColors.mutedForeground),
                  ),
                  const SizedBox(height: 14),
                  const Divider(),
                  const SizedBox(height: 8),
                  for (final p in f.points) CheckBullet(p),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading(
          tag: 'How it works',
          title: 'Embed. Register. Verify.',
          desc:
              'A simple three-step ownership lifecycle, backed by cryptographic binding and a persistent verification API.',
        ),
        const SizedBox(height: 24),
        for (final (n, title, desc) in _steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: EmCard(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(n, style: emMono(color: EmColors.primary)),
                      const SizedBox(width: 12),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(title, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    desc,
                    style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.5,
                        color: EmColors.mutedForeground),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: EmColors.background.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: EmColors.border),
          ),
          child: const Waveform(),
        ),
      ],
    );
  }
}

class _Goals extends StatelessWidget {
  const _Goals();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading(
          tag: 'Why Signata',
          title: 'Goals',
          desc: 'The principles driving every watermarking decision.',
        ),
        const SizedBox(height: 20),
        for (final g in _goals)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: EmCard(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: CheckBullet(g),
            ),
          ),
      ],
    );
  }
}

class _Architecture extends StatelessWidget {
  const _Architecture();

  static const _nodes = [
    ('Signata app', 'Protect · Trace · Verify'),
    ('On-device crypto', 'Account HMAC claim keys'),
    ('Fingerprint engines', 'Image · audio · video · PDF'),
    ('Local stores', 'History · radar · claims'),
  ];

  static const _engine = [
    'Image LSB watermark',
    'Audio WAV fingerprint',
    'Video / PDF structure marks',
    'Trace URL + share ingress',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading(
          tag: 'Architecture',
          title: 'Built to run on your device',
          desc:
              'Fingerprints, claim keys, and Trace history stay local. Optional remote registry is off unless you configure it.',
        ),
        const SizedBox(height: 24),
        for (var i = 0; i < _nodes.length; i++) ...[
          EmCard(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_nodes[i].$1,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: EmColors.foreground)),
                      const SizedBox(height: 2),
                      Text(_nodes[i].$2,
                          style: const TextStyle(
                              fontSize: 12,
                              color: EmColors.mutedForeground)),
                    ],
                  ),
                ),
                Text('0${i + 1}', style: emMono(color: EmColors.primary)),
              ],
            ),
          ),
          if (i < _nodes.length - 1)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Icon(Icons.arrow_downward,
                  size: 18, color: EmColors.primary),
            ),
        ],
        const SizedBox(height: 20),
        EmCard(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MonoLabel('Watermark Engine'),
              const SizedBox(height: 10),
              Text(
                'The processing core handles each media type with dedicated modules and a shared verification system.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: EmColors.mutedForeground, height: 1.5),
              ),
              const SizedBox(height: 16),
              for (final m in _engine)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: EmColors.background.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: EmColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: EmColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(m,
                          style: const TextStyle(
                              fontSize: 13.5, color: EmColors.foreground)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Technologies extends StatelessWidget {
  const _Technologies();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading(tag: 'Built with', title: 'Technologies'),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final t in _tech)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: EmColors.card,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: EmColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: EmColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(t,
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: EmColors.foreground)),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.onOpenTool});

  final void Function(EmTool) onOpenTool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading(
          tag: 'Project status',
          title: 'Currently in early research & prototype',
          desc:
              "Signata is being built milestone by milestone. Here's the roadmap ahead.",
        ),
        const SizedBox(height: 24),
        for (final (phase, active, title, items) in _milestones)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: EmCard(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: active
                              ? EmColors.accent
                              : EmColors.mutedForeground
                                  .withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      MonoLabel(
                        phase,
                        color: active
                            ? EmColors.accent
                            : EmColors.mutedForeground,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  for (final it in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 6),
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: EmColors.border,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(it,
                                style: const TextStyle(
                                    fontSize: 13.5,
                                    color: EmColors.mutedForeground)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        EmCard(
          glow: true,
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              Text('Want to follow the prototype?',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium),
              const SizedBox(height: 12),
              const Text(
                'The first milestone — image watermark embedding, extraction, and verification APIs — is underway. Try the working prototype right in this app.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: EmColors.mutedForeground),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => onOpenTool(EmTool.image),
                child: const Text('Open the live demo'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 36, 20, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EmLogo(),
          const SizedBox(height: 10),
          const Text(
            'Invisible ownership. Verifiable authenticity.',
            style:
                TextStyle(fontSize: 13, color: EmColors.mutedForeground),
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          Text(
            '© ${DateTime.now().year} Wejdan Al Amri · Signata · All rights reserved',
            style: const TextStyle(
                fontSize: 11, height: 1.45, color: EmColors.mutedForeground),
          ),
        ],
      ),
    );
  }
}
