import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../widgets/em_widgets.dart';

/// In-app Terms of Use for Signata.
class TermsOfUseScreen extends StatelessWidget {
  const TermsOfUseScreen({super.key});

  static const lastUpdated = 'August 14, 2026';
  static const supportEmail = 'FocusMindDev@gmail.com';
  static const licenseUrl =
      'https://github.com/WejdanBa-CS/Signata/blob/main/LICENSE';

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const TermsOfUseScreen(),
      ),
    );
  }

  Future<void> _mailSupport() async {
    final uri = Uri(
      scheme: 'mailto',
      path: supportEmail,
      queryParameters: {'subject': 'Signata terms inquiry'},
    );
    await launchUrl(uri);
  }

  Future<void> _openLicense() async {
    final uri = Uri.parse(licenseUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EmColors.background,
      appBar: AppBar(
        title: const Text('Terms of Use'),
        backgroundColor: EmColors.background,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          const SectionHeading(
            tag: 'Legal',
            title: 'Terms of Use',
            desc: 'Last updated: August 14, 2026',
          ),
          const SizedBox(height: 16),
          EmCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'By using Signata you agree to these terms. If you do not agree, '
                  'please do not use the app.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.55,
                    color: EmColors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 22),
                const _Section(
                  number: '1',
                  title: 'The service',
                  body:
                      'Signata is a digital watermarking and ownership verification tool. '
                      'Protect, verify, and trace media on your device. Purchases or '
                      'distribution of protected files happen outside Signata.',
                ),
                const _Section(
                  number: '2',
                  title: 'Your account',
                  body:
                      'You are responsible for activity under your account, your claim key, '
                      'and content you protect or trace. Do not use Signata for illegal, '
                      'harmful, or infringing material.',
                ),
                const _Section(
                  number: '3',
                  title: 'On-device processing',
                  body:
                      'By default, accounts, claim keys, history, and trace data stay on '
                      'this device. Export a recovery kit before wiping the device. '
                      'Optional registry integrations may publish fingerprint metadata you choose.',
                ),
                const _Section(
                  number: '4',
                  title: 'Intellectual property',
                  body:
                      'Signata, its design, code, and branding are owned by Wejdan Al Amri. '
                      'You may not copy, scrape, or clone the app or service for commercial use. '
                      'Source is published under the terms in our LICENSE.',
                ),
                TextButton.icon(
                  onPressed: _openLicense,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('View LICENSE on GitHub'),
                  style: TextButton.styleFrom(
                    foregroundColor: EmColors.primary,
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerLeft,
                  ),
                ),
                const SizedBox(height: 14),
                const _Section(
                  number: '5',
                  title: 'Disclaimer',
                  body:
                      'Signata is provided as-is. We do not guarantee uninterrupted service, '
                      'that third-party platforms will preserve fingerprints, or that trace results '
                      'prove legal ownership in every jurisdiction. To the fullest extent allowed '
                      'by law, we are not liable for indirect or consequential damages arising from '
                      'use of the app.',
                ),
                const _Section(
                  number: '6',
                  title: 'Changes',
                  body:
                      'We may update these terms. Continued use after changes means you accept '
                      'the updated terms.',
                ),
                const _Section(
                  number: '7',
                  title: 'Contact',
                  body: 'Questions about these terms:',
                ),
                TextButton.icon(
                  onPressed: _mailSupport,
                  icon: const Icon(Icons.mail_outline, size: 18),
                  label: const Text(supportEmail),
                  style: TextButton.styleFrom(
                    foregroundColor: EmColors.primary,
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerLeft,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.number,
    required this.title,
    required this.body,
  });

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$number. $title',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: EmColors.foreground,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              fontSize: 14,
              height: 1.55,
              color: EmColors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}
