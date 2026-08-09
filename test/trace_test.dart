import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signata/core/claim_crypto.dart';
import 'package:signata/core/claim_registry.dart';
import 'package:signata/core/trace_models.dart';
import 'package:signata/core/trace_store.dart';
import 'package:signata/core/url_tracer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ClaimRegistry.configure(remoteBaseUrl: '');
  });

  group('claim registry', () {
    test('publishes and finds claims locally by reference', () async {
      final published = await ClaimRegistry.instance.publish(
        medium: TraceMedium.image,
        owner: 'Studio Nova',
        subject: 'art.png·120x90',
        reference: 'ABC123HMAC',
        issued: '2026-01-01T00:00:00Z',
        alg: 'hmac-sha256',
        kid: 'DEADBEEF',
      );
      expect(published.remoteSynced, isFalse);
      final found =
          await ClaimRegistry.instance.findByReference('abc123hmac');
      expect(found, isNotNull);
      expect(found!.owner, 'Studio Nova');
      expect(found.subject, 'art.png·120x90');
    });
  });

  group('trace store', () {
    test('watchlist and sightings persist', () async {
      final watch = await TraceStore.instance.addWatchTarget(
        'https://cdn.example.com/a.png',
        label: 'Portfolio',
      );
      expect(watch.url, contains('cdn.example.com'));
      final listed = await TraceStore.instance.listWatchTargets();
      expect(listed.length, 1);

      await TraceStore.instance.addSighting(TraceSighting(
        id: 's1',
        url: watch.url,
        medium: TraceMedium.image,
        at: DateTime.utc(2026, 1, 2),
        found: true,
        claimStatus: ClaimStatus.authenticated,
        owner: 'Studio Nova',
        reference: 'ABC',
      ));
      final sightings = await TraceStore.instance.listSightings();
      expect(sightings.first.found, isTrue);
      expect(sightings.first.claimStatus, ClaimStatus.authenticated);
    });
  });

  group('url tracer', () {
    test('rejects non-http urls', () async {
      expect(
        () => UrlTracer.instance.scanUrl('ftp://x/y.png', persist: false),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('published claim JSON round-trips', () {
      final claim = PublishedClaim(
        id: 'c1',
        medium: TraceMedium.pdf,
        owner: 'A',
        subject: 'd.pdf',
        reference: 'ID',
        issued: 't',
        publisherId: 'u',
        publishedAt: DateTime.utc(2026),
      );
      final again =
          PublishedClaim.fromJson(jsonDecode(jsonEncode(claim.toJson())));
      expect(again?.medium, TraceMedium.pdf);
      expect(again?.reference, 'ID');
    });
  });
}
