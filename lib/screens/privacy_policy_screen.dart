import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../widgets/em_widgets.dart';

/// In-app Privacy Policy for Signata (PDPL / Kingdom of Saudi Arabia).
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const lastUpdated = 'August 10, 2026';
  static const supportEmail = 'FocusMindDev@gmail.com';

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PrivacyPolicyScreen(),
      ),
    );
  }

  Future<void> _mailSupport() async {
    final uri = Uri(
      scheme: 'mailto',
      path: supportEmail,
      queryParameters: {'subject': 'Signata privacy inquiry'},
    );
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EmColors.background,
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        backgroundColor: EmColors.background,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          const SectionHeading(
            tag: 'Legal',
            title: 'Privacy Policy for Signata',
            desc: 'Last updated: August 10, 2026',
          ),
          const SizedBox(height: 16),
          EmCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Intro(),
                const SizedBox(height: 22),
                const _Section(
                  number: '1',
                  title: 'Data We Collect and Process',
                  body:
                      'Given Signata\'s nature as a digital watermarking and ownership verification platform, we handle specific categories of data:',
                  bullets: [
                    'Basic Account Data: Upon registration, we collect the necessary information to create and manage your account (e.g., name, email address, and authentication data).',
                    'Media Files: This includes images (PNG, JPG), audio (WAV), video clips (MP4/MOV), and documents (PDF) that you protect or verify using the app.',
                    'Metadata & Encrypted Fingerprints: We process and generate structural identifiers (such as SHA-256) and hidden encrypted fingerprints to prove content ownership.',
                    'Trace Data & Public URLs: The public links you input into the "Trace" tool to scan for your content on platforms like Instagram, TikTok, and X.',
                  ],
                ),
                const _Section(
                  number: '2',
                  title: 'On-Device Verification & Processing',
                  body:
                      'At Signata, the security and privacy of your content are our top priorities:',
                  bullets: [
                    'Media Protection: Embedding watermarks, audio fingerprints, and structural identifiers for videos and documents runs locally on your device.',
                    'By default Signata does not upload your original media or claim keys to Signata servers. History, Trace radar, and published claims stay in on-device storage scoped to your account.',
                    'If you later configure an optional self-hosted claim registry, only fingerprint metadata you choose to publish may leave the device — never your original files.',
                  ],
                ),
                const _Section(
                  number: '3',
                  title: 'How We Use Your Data',
                  body:
                      'The data we collect is strictly used for the following purposes:',
                  bullets: [
                    'To enable you to embed hidden ownership fingerprints in media without altering its visual or auditory quality.',
                    'To operate the Radar and Trace services, scanning public links and matching them against your registered fingerprints to detect unauthorized use.',
                    'To improve our hidden fingerprint algorithms and their robustness against common modifications (such as compression, cropping, and color shifts).',
                    'To provide technical support and manage your account.',
                  ],
                ),
                const _Section(
                  number: '4',
                  title: 'Third-Party Services and External Links',
                  body: null,
                  bullets: [
                    'Trace Tool: This tool interacts with the public interfaces of platforms (like Instagram, TikTok, and X) to scan the links you provide. We do not control the privacy practices of these platforms, and your interaction with them is governed by their respective privacy policies.',
                    'We will never share your Trace logs, search history, or encrypted fingerprints with any third parties for marketing or advertising purposes.',
                  ],
                ),
                const _Section(
                  number: '5',
                  title: 'Data Security',
                  body:
                      'We implement industry-standard security protocols and advanced encryption (including SHA-256 hashing algorithms) to protect your data from unauthorized access, alteration, or disclosure. The binding of encrypted structural identifiers ensures that your proof of ownership remains secure and tamper-proof.',
                ),
                const _Section(
                  number: '6',
                  title: 'User Rights (Access and Deletion)',
                  body:
                      'In accordance with applicable data protection laws, you have the right to:',
                  bullets: [
                    'Access: View your ownership records (History) and actively tracked links (Watching) directly in the app.',
                    'Deletion: Use Account → Delete account to erase your local Signata account record, claim key, history, Trace data, and usage flags on this device. This does not remove watermarks already embedded in exported files. Email FocusMindDev@gmail.com for privacy requests beyond what the app can erase locally.',
                  ],
                ),
                const _Section(
                  number: '7',
                  title: 'Governing Law and Policy Updates',
                  body:
                      'This Privacy Policy is governed by and construed in accordance with the applicable laws of the Kingdom of Saudi Arabia, primarily the Personal Data Protection Law (PDPL). We may update this policy periodically, and we will notify you of any material changes via the app or email.',
                ),
                const _Section(
                  number: '8',
                  title: 'Contact Us',
                  body:
                      'For any legal or technical inquiries regarding your privacy and data management, please contact us at:',
                ),
                const SizedBox(height: 8),
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

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'At Signata, we are fully committed to protecting the privacy of our users and securing digital content with the highest security standards. This Privacy Policy explains how we collect, use, process, and protect your personal data, media files, and the links you trace through our platform.',
      style: TextStyle(
        fontSize: 14,
        height: 1.55,
        color: EmColors.mutedForeground,
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.number,
    required this.title,
    required this.body,
    this.bullets,
  });

  final String number;
  final String title;
  final String? body;
  final List<String>? bullets;

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
          if (body != null) ...[
            const SizedBox(height: 8),
            Text(
              body!,
              style: const TextStyle(
                fontSize: 14,
                height: 1.55,
                color: EmColors.mutedForeground,
              ),
            ),
          ],
          if (bullets != null) ...[
            const SizedBox(height: 10),
            for (final item in bullets!)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 7, right: 10),
                      child: Icon(Icons.circle,
                          size: 6, color: EmColors.primary),
                    ),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.55,
                          color: EmColors.mutedForeground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
