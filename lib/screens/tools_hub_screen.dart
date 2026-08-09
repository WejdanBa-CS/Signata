import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/em_widgets.dart';

enum EmTool { image, audio, video, pdf, trace }

class ToolsHubScreen extends StatelessWidget {
  const ToolsHubScreen({super.key, required this.onOpenTool});

  final void Function(EmTool tool) onOpenTool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      children: [
        const SectionHeading(
          tag: 'Workspace',
          title: 'Protect & verify',
          desc:
              'Protect files on-device, then trace public URLs across the internet for Signata fingerprints.',
        ),
        const SizedBox(height: 20),
        _ToolTile(
          tag: '01 / Visual',
          title: 'Image watermark',
          desc: 'Hide an ownership fingerprint in the pixels of a PNG or JPG.',
          icon: Icons.image_outlined,
          tone: EmColors.primary,
          onTap: () => onOpenTool(EmTool.image),
        ),
        _ToolTile(
          tag: '02 / Audio',
          title: 'Audio watermark',
          desc: 'Embed an inaudible claim into a 16-bit WAV clip.',
          icon: Icons.graphic_eq,
          tone: EmColors.primary,
          onTap: () => onOpenTool(EmTool.audio),
        ),
        _ToolTile(
          tag: '03 / Video',
          title: 'Video fingerprint',
          desc: 'Profile an MP4/MOV and bind a structural ownership identifier.',
          icon: Icons.movie_outlined,
          tone: EmColors.accent,
          onTap: () => onOpenTool(EmTool.video),
        ),
        _ToolTile(
          tag: '04 / Documents',
          title: 'PDF fingerprint',
          desc: 'Derive a SHA-256 structural ID and hide it in the delivered file.',
          icon: Icons.description_outlined,
          tone: EmColors.accent,
          onTap: () => onOpenTool(EmTool.pdf),
        ),
        _ToolTile(
          tag: '05 / Internet',
          title: 'Trace online',
          desc:
              'Scan public media URLs, watch links for reappearance, and match fingerprints to your published claims.',
          icon: Icons.travel_explore,
          tone: EmColors.primary,
          onTap: () => onOpenTool(EmTool.trace),
        ),
        const SizedBox(height: 12),
        Text(
          'Tip: protect a file, publish the claim, then Trace any URL where a copy might appear.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: EmColors.mutedForeground, height: 1.45),
        ),
      ],
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.tag,
    required this.title,
    required this.desc,
    required this.icon,
    required this.tone,
    required this.onTap,
  });

  final String tag;
  final String title;
  final String desc;
  final IconData icon;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: EmCard(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: tone),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MonoLabel(tag, color: tone),
                      const SizedBox(height: 6),
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: EmColors.foreground)),
                      const SizedBox(height: 4),
                      Text(desc,
                          style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: EmColors.mutedForeground)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: EmColors.mutedForeground),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
