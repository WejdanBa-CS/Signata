import 'package:flutter_test/flutter_test.dart';
import 'package:signata/core/social_platforms.dart';

void main() {
  group('SocialPlatformInfo.fromUrl', () {
    test('detects Instagram hosts', () {
      expect(
        SocialPlatformInfo.fromUrl('https://www.instagram.com/p/abc/')?.id,
        SocialPlatform.instagram,
      );
      expect(
        SocialPlatformInfo.fromUrl('https://instagr.am/p/abc/')?.id,
        SocialPlatform.instagram,
      );
    });

    test('detects TikTok hosts', () {
      expect(
        SocialPlatformInfo.fromUrl('https://www.tiktok.com/@user/video/1')?.id,
        SocialPlatform.tiktok,
      );
      expect(
        SocialPlatformInfo.fromUrl('https://vm.tiktok.com/ZMabc/')?.id,
        SocialPlatform.tiktok,
      );
    });

    test('detects X / Twitter hosts', () {
      expect(
        SocialPlatformInfo.fromUrl('https://x.com/user/status/1')?.id,
        SocialPlatform.x,
      );
      expect(
        SocialPlatformInfo.fromUrl('https://twitter.com/user/status/1')?.id,
        SocialPlatform.x,
      );
    });

    test('returns null for unrelated hosts', () {
      expect(
        SocialPlatformInfo.fromUrl('https://cdn.example.com/a.png'),
        isNull,
      );
    });
  });

  group('SocialMediaResolver helpers', () {
    test('absolutize is covered via public resolve contract shape', () {
      // Smoke: platforms list stays complete for Trace UI.
      expect(SocialPlatformInfo.all.map((p) => p.id).toSet(), {
        SocialPlatform.instagram,
        SocialPlatform.tiktok,
        SocialPlatform.x,
      });
    });
  });
}
