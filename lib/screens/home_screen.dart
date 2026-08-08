import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/em_widgets.dart';

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
    '03 / Documents',
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
    'Embed',
    'An encrypted fingerprint is encoded into the media imperceptibly, preserving the original experience.'
  ),
  (
    '02',
    'Register',
    "Ownership metadata is stored and cryptographically bound to the creator's identity in the database."
  ),
  (
    '03',
    'Verify',
    'Any distributed copy can be scanned to extract the fingerprint and confirm authenticity and ownership.'
  ),
];

const _goals = [
  'Protect creators from unauthorized redistribution',
  'Preserve ownership information across platforms',
  'Build a reliable verification system',
  'Research robust watermark persistence techniques',
  'Explore anti-tampering and anti-removal methods',
];

const _tech = [
  'Python',
  'FastAPI',
  'OpenCV',
  'NumPy',
  'Cryptography',
  'PostgreSQL',
];

const _milestones = [
  (
    'In progress',
    true,
    'Image watermark foundation',
    [
      'Image watermark embedding',
      'Watermark extraction',
      'Ownership verification APIs',
    ]
  ),
  (
    'Planned',
    false,
    'Audio & document pipelines',
    [
      'Audio fingerprint embedding',
      'PDF structural fingerprinting',
      'Cross-format verification',
    ]
  ),
  (
    'Planned',
    false,
    'Hardening & research',
    [
      'Anti-tamper resilience',
      'Robustness benchmarking',
      'Production verification API',
    ]
  ),
];

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onOpenTool});

  /// Jumps to a tool tab: 1 = image, 2 = pdf.
  final void Function(int tabIndex) onOpenTool;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _Hero(onOpenTool: onOpenTool),
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

  final void Function(int) onOpenTool;

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
                'EchoMark embeds hidden, encrypted fingerprints inside images, audio, and PDFs — preserving the original experience while letting creators prove ownership and authenticity of their work.',
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
                    onPressed: () => onOpenTool(1),
                    child: const Text('Try the image tool'),
                  ),
                  OutlinedButton(
                    onPressed: () => onOpenTool(2),
                    child: const Text('Fingerprint a PDF'),
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
    ('3', 'Media formats supported'),
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
          title: 'One platform, three media formats',
          desc:
              'EchoMark protects digital content across the formats creators actually ship — without altering how it looks or sounds.',
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
          tag: 'Why EchoMark',
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
    ('Client', 'Upload & verify'),
    ('FastAPI Backend', 'REST API layer'),
    ('Watermark Engine', 'Processing core'),
    ('Database', 'Ownership records'),
  ];

  static const _engine = [
    'Image Processing',
    'Audio Processing',
    'PDF Fingerprinting',
    'Verification System',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading(
          tag: 'Planned architecture',
          title: 'A layered watermarking pipeline',
          desc:
              'From client request to encrypted fingerprint to verified ownership record.',
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

  final void Function(int) onOpenTool;

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
              "EchoMark is being built milestone by milestone. Here's the roadmap ahead.",
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
                onPressed: () => onOpenTool(1),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '© ${DateTime.now().year} EchoMark',
                style: const TextStyle(
                    fontSize: 11, color: EmColors.mutedForeground),
              ),
              Text('RESEARCH & PROTOTYPE PHASE',
                  style: emMonoLabel(
                      color: EmColors.mutedForeground, size: 9)),
            ],
          ),
        ],
      ),
    );
  }
}
