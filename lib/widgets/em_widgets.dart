import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Concentric fingerprint rings — the "hidden identity" logo motif.
class EmLogo extends StatelessWidget {
  const EmLogo({super.key, this.size = 28, this.showWordmark = true});

  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(
      size: Size.square(size),
      painter: _LogoPainter(color: EmColors.foreground),
    );
    if (!showWordmark) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 10),
        Text(
          'EchoMark',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(letterSpacing: -0.4),
        ),
      ],
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 28;
    final center = Offset(size.width / 2, size.height / 2);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * s
      ..strokeCap = StrokeCap.round;

    stroke.color = color.withValues(alpha: 0.35);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(1.5 * s, 1.5 * s, 25 * s, 25 * s),
        Radius.circular(7 * s),
      ),
      stroke,
    );

    stroke.strokeWidth = 1.4 * s;
    stroke.color = color.withValues(alpha: 0.55);
    canvas.drawCircle(center, 9.5 * s, stroke);
    stroke.color = color.withValues(alpha: 0.8);
    canvas.drawCircle(center, 6 * s, stroke);

    canvas.drawCircle(center, 2.5 * s, Paint()..color = color);

    stroke.color = color;
    final arc = Rect.fromCircle(center: center, radius: 9.5 * s);
    canvas.drawArc(arc, -math.pi / 2, math.pi / 3, false, stroke);
  }

  @override
  bool shouldRepaint(covariant _LogoPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Uppercase tracked monospace label (`em-mono-label`).
class MonoLabel extends StatelessWidget {
  const MonoLabel(this.text, {super.key, this.color = EmColors.primary});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: emMonoLabel(color: color));
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.tag,
    required this.title,
    this.desc,
  });

  final String tag;
  final String title;
  final String? desc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MonoLabel(tag),
        const SizedBox(height: 12),
        Text(title, style: theme.textTheme.displayMedium),
        if (desc != null) ...[
          const SizedBox(height: 12),
          Text(
            desc!,
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: EmColors.mutedForeground, height: 1.5),
          ),
        ],
      ],
    );
  }
}

/// Rounded bordered card (`em-card`).
class EmCard extends StatelessWidget {
  const EmCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.borderColor = EmColors.border,
    this.glow = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color borderColor;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: EmColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: EmColors.primary.withValues(alpha: 0.25),
                  blurRadius: 40,
                  spreadRadius: -8,
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

/// Emerald check bullet used across feature lists and goals.
class CheckBullet extends StatelessWidget {
  const CheckBullet(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: EmColors.accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, size: 13, color: EmColors.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  color: EmColors.foreground, fontSize: 14, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// Verified / failed status banner used in both tools' reports.
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.ok,
    required this.title,
    required this.subtitle,
  });

  final bool ok;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final color = ok ? EmColors.accent : EmColors.destructive;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(ok ? Icons.check : Icons.close, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: EmColors.foreground)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: EmColors.mutedForeground)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Label/value row inside a bordered detail list.
class DetailRow extends StatelessWidget {
  const DetailRow(this.label, this.value, {super.key, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: emMonoLabel(color: EmColors.mutedForeground, size: 10)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: mono
                  ? emMono(size: 11)
                  : const TextStyle(fontSize: 13, color: EmColors.foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class DetailList extends StatelessWidget {
  const DetailList({super.key, required this.rows});

  final List<DetailRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EmColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// Animated signal waveform motif from the "How it works" section.
class Waveform extends StatefulWidget {
  const Waveform({super.key, this.bars = 40, this.height = 44});

  final int bars;
  final double height;

  @override
  State<Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<Waveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(widget.bars, (i) {
              final phase = (_controller.value - i * 0.043) % 1.0;
              final t = math.sin(phase * 2 * math.pi) * 0.5 + 0.5;
              final scale = 0.4 + t * 0.6;
              return Container(
                width: 3,
                height: widget.height * scale,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  color: EmColors.primary
                      .withValues(alpha: 0.35 + t * 0.65),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

/// Fine background grid used behind the hero and section backdrops.
class GridBackdrop extends StatelessWidget {
  const GridBackdrop({super.key, this.spacing = 28, this.opacity = 0.04});

  final double spacing;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _GridPainter(spacing: spacing, opacity: opacity),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter({required this.spacing, required this.opacity});

  final double spacing;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.spacing != spacing || oldDelegate.opacity != opacity;
}

/// Dashed-border upload drop zone.
class UploadBox extends StatelessWidget {
  const UploadBox({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    required this.buttonLabel,
    required this.onPick,
    this.fileName,
    this.tone = EmColors.primary,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String hint;
  final String buttonLabel;
  final VoidCallback onPick;
  final String? fileName;
  final Color tone;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: EmColors.background.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EmColors.border),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: tone, size: 24),
          ),
          const SizedBox(height: 14),
          Text(title,
              style:
                  const TextStyle(fontSize: 14, color: EmColors.foreground)),
          const SizedBox(height: 4),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 12, color: EmColors.mutedForeground),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : onPick,
            style: FilledButton.styleFrom(
              backgroundColor: tone,
              foregroundColor: tone == EmColors.accent
                  ? EmColors.accentForeground
                  : EmColors.primaryForeground,
            ),
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(buttonLabel),
          ),
          if (fileName != null) ...[
            const SizedBox(height: 14),
            Text(
              fileName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: emMono(color: EmColors.mutedForeground, size: 11),
            ),
          ],
        ],
      ),
    );
  }
}

/// Collapsible raw payload viewer.
class PayloadViewer extends StatelessWidget {
  const PayloadViewer({super.key, required this.title, required this.raw});

  final String title;
  final String? raw;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: EmColors.background.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EmColors.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: Text(title.toUpperCase(),
              style: emMonoLabel(color: EmColors.mutedForeground, size: 10)),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(raw ?? 'null', style: emMono(size: 11)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
