/// Social surfaces Signata can protect media for and scan links from.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'safe_url.dart';

enum SocialPlatform { instagram, tiktok, x, other }

class SocialPlatformInfo {
  const SocialPlatformInfo({
    required this.id,
    required this.label,
    required this.shortLabel,
    required this.hint,
    required this.androidPackages,
    required this.urlSchemes,
    required this.hostMatchers,
    required this.accent,
    required this.icon,
  });

  final SocialPlatform id;
  final String label;
  final String shortLabel;
  final String hint;
  final List<String> androidPackages;
  final List<String> urlSchemes;
  final List<String> hostMatchers;
  final int accent; // ARGB
  final String icon; // material icon name key used by UI

  static const instagram = SocialPlatformInfo(
    id: SocialPlatform.instagram,
    label: 'Instagram',
    shortLabel: 'IG',
    hint: 'Best: share the Reel/photo into Signata. Post URLs often hide the real file.',
    androidPackages: ['com.instagram.android'],
    urlSchemes: ['instagram'],
    hostMatchers: ['instagram.com', 'www.instagram.com', 'instagr.am'],
    accent: 0xFFE1306C,
    icon: 'photo_camera_outlined',
  );

  static const tiktok = SocialPlatformInfo(
    id: SocialPlatform.tiktok,
    label: 'TikTok',
    shortLabel: 'TT',
    hint: 'Best: share the video file into Signata. TikTok page links rarely expose media.',
    androidPackages: [
      'com.zhiliaoapp.musically',
      'com.ss.android.ugc.trill',
      'com.ss.android.ugc.tiktok',
    ],
    urlSchemes: ['tiktok', 'snssdk1128'],
    hostMatchers: [
      'tiktok.com',
      'www.tiktok.com',
      'vm.tiktok.com',
      'vt.tiktok.com',
      'm.tiktok.com',
    ],
    accent: 0xFF25F4EE,
    icon: 'music_note_outlined',
  );

  static const x = SocialPlatformInfo(
    id: SocialPlatform.x,
    label: 'X',
    shortLabel: 'X',
    hint: 'Best: share the image/clip into Signata. X post links are a fallback only.',
    androidPackages: ['com.twitter.android'],
    urlSchemes: ['twitter', 'x'],
    hostMatchers: [
      'x.com',
      'www.x.com',
      'twitter.com',
      'www.twitter.com',
      'mobile.twitter.com',
      't.co',
    ],
    accent: 0xFFEFF3F4,
    icon: 'tag_outlined',
  );

  static const all = [instagram, tiktok, x];

  static SocialPlatformInfo? fromUrl(String rawUrl) {
    final host = Uri.tryParse(rawUrl.trim())?.host.toLowerCase() ?? '';
    for (final platform in all) {
      for (final matcher in platform.hostMatchers) {
        if (host == matcher || host.endsWith('.$matcher')) {
          return platform;
        }
      }
    }
    return null;
  }

  Future<bool> openApp() async {
    for (final scheme in urlSchemes) {
      final uri = Uri.parse('$scheme://');
      if (await canLaunchUrl(uri)) {
        return launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
    // Fall back to the public web home.
    final web = switch (id) {
      SocialPlatform.instagram => Uri.parse('https://www.instagram.com/'),
      SocialPlatform.tiktok => Uri.parse('https://www.tiktok.com/'),
      SocialPlatform.x => Uri.parse('https://x.com/'),
      SocialPlatform.other => null,
    };
    if (web == null) return false;
    return launchUrl(web, mode: LaunchMode.externalApplication);
  }
}

/// Tries to turn a social post page into a direct media URL via Open Graph tags.
class SocialMediaResolver {
  SocialMediaResolver._();
  static final SocialMediaResolver instance = SocialMediaResolver._();

  static const _ua =
      'Mozilla/5.0 (compatible; SignataTrace/1.0; +https://signata.app)';

  Future<ResolvedSocialMedia?> resolve(String rawUrl) async {
    final parsed = SafeUrl.parseTraceUrl(rawUrl);
    if (!parsed.isOk) {
      final platform = SocialPlatformInfo.fromUrl(rawUrl);
      if (platform == null) return null;
      return ResolvedSocialMedia(
        platform: platform,
        pageUrl: rawUrl.trim(),
        mediaUrl: null,
        note: parsed.error,
      );
    }
    final url = parsed.uri!.toString();
    final platform = SocialPlatformInfo.fromUrl(url);
    if (platform == null) return null;

    try {
      final response = await http
          .get(
            parsed.uri!,
            headers: {
              'User-Agent': _ua,
              'Accept': 'text/html,application/xhtml+xml',
            },
          )
          .timeout(const Duration(seconds: 25));
      if (response.statusCode < 200 || response.statusCode >= 400) {
        return ResolvedSocialMedia(
          platform: platform,
          pageUrl: url,
          mediaUrl: null,
          note:
              'Could not open that ${platform.label} page (${response.statusCode}). '
              'Share the media file into Signata instead.',
        );
      }

      final html = utf8.decode(response.bodyBytes, allowMalformed: true);
      final mediaUrl = _firstMatch(html, const [
            r'property="og:video:secure_url"\s+content="([^"]+)"',
            r"property='og:video:secure_url'\s+content='([^']+)'",
            r'property="og:video"\s+content="([^"]+)"',
            r"property='og:video'\s+content='([^']+)'",
            r'content="([^"]+)"\s+property="og:video"',
            r'name="twitter:player:stream"\s+content="([^"]+)"',
            r'property="og:image:secure_url"\s+content="([^"]+)"',
            r'property="og:image"\s+content="([^"]+)"',
            r"property='og:image'\s+content='([^']+)'",
            r'content="([^"]+)"\s+property="og:image"',
            r'name="twitter:image"\s+content="([^"]+)"',
          ]) ??
          _jsonLdMedia(html);

      if (mediaUrl == null || mediaUrl.isEmpty) {
        return ResolvedSocialMedia(
          platform: platform,
          pageUrl: url,
          mediaUrl: null,
          note:
              '${platform.label} did not expose a public media file for this link. '
              'In the app: Share → Signata, or save the file and Protect & post here.',
        );
      }

      final absolute = _absolutize(mediaUrl, url);
      final mediaParsed = SafeUrl.parseTraceUrl(absolute);
      if (!mediaParsed.isOk) {
        return ResolvedSocialMedia(
          platform: platform,
          pageUrl: url,
          mediaUrl: null,
          note: mediaParsed.error ?? 'Resolved media URL was blocked for security.',
        );
      }

      return ResolvedSocialMedia(
        platform: platform,
        pageUrl: url,
        mediaUrl: mediaParsed.uri!.toString(),
        note: null,
      );
    } catch (error) {
      return ResolvedSocialMedia(
        platform: platform,
        pageUrl: url,
        mediaUrl: null,
        note: error.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  static String? _firstMatch(String html, List<String> patterns) {
    for (final pattern in patterns) {
      final match =
          RegExp(pattern, caseSensitive: false).firstMatch(html)?.group(1);
      if (match != null && match.trim().isNotEmpty) {
        return match.trim().replaceAll('&amp;', '&');
      }
    }
    return null;
  }

  static String? _jsonLdMedia(String html) {
    final blocks = RegExp(
      r'<script[^>]+type="application/ld\+json"[^>]*>([\s\S]*?)</script>',
      caseSensitive: false,
    ).allMatches(html);
    for (final block in blocks) {
      final raw = block.group(1)?.trim();
      if (raw == null || raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        final found = _walkForMedia(decoded);
        if (found != null) return found;
      } catch (_) {}
    }
    return null;
  }

  static String? _walkForMedia(Object? node) {
    if (node is Map) {
      for (final key in ['contentUrl', 'url', 'image', 'thumbnailUrl']) {
        final value = node[key];
        if (value is String &&
            (value.startsWith('http://') || value.startsWith('https://')) &&
            _looksLikeMedia(value)) {
          return value;
        }
        if (value is List) {
          for (final item in value) {
            final nested = _walkForMedia(item);
            if (nested != null) return nested;
          }
        }
        if (value is Map) {
          final nested = _walkForMedia(value);
          if (nested != null) return nested;
        }
      }
      for (final value in node.values) {
        final nested = _walkForMedia(value);
        if (nested != null) return nested;
      }
    } else if (node is List) {
      for (final item in node) {
        final nested = _walkForMedia(item);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  static bool _looksLikeMedia(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.mp4') ||
        lower.contains('.mov') ||
        lower.contains('.jpg') ||
        lower.contains('.jpeg') ||
        lower.contains('.png') ||
        lower.contains('.webp') ||
        lower.contains('video') ||
        lower.contains('image') ||
        lower.contains('media');
  }

  static String _absolutize(String mediaUrl, String pageUrl) {
    final media = Uri.tryParse(mediaUrl);
    if (media == null) return mediaUrl;
    if (media.hasScheme) return mediaUrl;
    return Uri.parse(pageUrl).resolveUri(media).toString();
  }
}

class ResolvedSocialMedia {
  const ResolvedSocialMedia({
    required this.platform,
    required this.pageUrl,
    required this.mediaUrl,
    required this.note,
  });

  final SocialPlatformInfo platform;
  final String pageUrl;
  final String? mediaUrl;
  final String? note;
}
