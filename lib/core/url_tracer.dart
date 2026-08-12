/// Fetches a public media URL and scans it for a Signata fingerprint.
library;

import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'audio_watermark.dart';
import 'claim_crypto.dart';
import 'claim_registry.dart';
import 'image_watermark.dart';
import 'pdf_fingerprint.dart';
import 'social_platforms.dart';
import 'trace_models.dart';
import 'trace_store.dart';
import 'video_fingerprint.dart';

class TraceScanResult {
  const TraceScanResult({
    required this.sighting,
    this.matchedClaim,
    this.bytes,
  });

  final TraceSighting sighting;
  final PublishedClaim? matchedClaim;
  final Uint8List? bytes;
}

class UrlTracer {
  UrlTracer._();
  static final UrlTracer instance = UrlTracer._();

  static const _maxBytes = 40 * 1024 * 1024;

  Future<TraceScanResult> scanUrl(
    String rawUrl, {
    ClaimKey? claimKey,
    bool persist = true,
    bool addToWatchlist = false,
  }) async {
    final url = rawUrl.trim();
    if (!_looksLikeHttpUrl(url)) {
      throw ArgumentError('Enter a valid http(s) URL to a media file.');
    }

    var fetchUrl = url;
    String? socialNote;
    final social = SocialPlatformInfo.fromUrl(url);
    if (social != null && !_looksLikeDirectMedia(url)) {
      final resolved = await SocialMediaResolver.instance.resolve(url);
      socialNote = resolved?.note;
      if (resolved?.mediaUrl != null && resolved!.mediaUrl!.isNotEmpty) {
        fetchUrl = resolved.mediaUrl!;
      } else if (resolved != null) {
        final sighting = TraceSighting(
          id: _id(),
          url: url,
          medium: TraceMedium.unknown,
          at: DateTime.now().toUtc(),
          found: false,
          claimStatus: ClaimStatus.missing,
          error: resolved.note ??
              '${social.label} link could not be resolved to a media file.',
        );
        if (persist) await TraceStore.instance.addSighting(sighting);
        if (addToWatchlist) {
          final watch = await TraceStore.instance.addWatchTarget(
            url,
            label: social.label,
          );
          await TraceStore.instance.touchWatchTarget(
            watch.id,
            reference: null,
          );
        }
        return TraceScanResult(sighting: sighting);
      }
    }

    Uint8List bytes;
    String? contentType;
    try {
      final response = await http.get(
        Uri.parse(fetchUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (compatible; SignataTrace/1.0; +https://signata.app)',
          'Accept': '*/*',
        },
      ).timeout(
        const Duration(seconds: 45),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Download failed (${response.statusCode}).');
      }
      if (response.bodyBytes.length > _maxBytes) {
        throw Exception('File is larger than 40 MB; try a direct media link.');
      }
      bytes = response.bodyBytes;
      contentType = response.headers['content-type'];
    } catch (error) {
      final message = socialNote ??
          error.toString().replaceFirst('Exception: ', '');
      final sighting = TraceSighting(
        id: _id(),
        url: url,
        medium: TraceMedium.unknown,
        at: DateTime.now().toUtc(),
        found: false,
        claimStatus: ClaimStatus.missing,
        error: message,
      );
      if (persist) await TraceStore.instance.addSighting(sighting);
      return TraceScanResult(sighting: sighting);
    }

    final medium = _detectMedium(url: url, contentType: contentType, bytes: bytes);
    final extracted = await _extract(medium, bytes, claimKey);
    PublishedClaim? matched;
    if (extracted.reference != null && extracted.reference!.isNotEmpty) {
      matched = await ClaimRegistry.instance.findByReference(extracted.reference!);
    }

    final sighting = TraceSighting(
      id: _id(),
      url: url,
      medium: medium,
      at: DateTime.now().toUtc(),
      found: extracted.found,
      claimStatus: extracted.status,
      owner: extracted.owner ?? matched?.owner,
      subject: extracted.subject ?? matched?.subject,
      reference: extracted.reference ?? matched?.reference,
      matchedPublishedClaimId: matched?.id,
      contentType: contentType,
      note: !extracted.found
          ? (social != null
              ? '${social.label} often recompresses uploads, which can strip '
                  'hidden fingerprints. If you posted a Signata-protected file, '
                  'try scanning the original export or a direct CDN media URL.'
              : 'No Signata fingerprint was readable in this file. If it was '
                  're-saved, compressed, or re-encoded, the mark may be gone.')
          : null,
    );

    if (persist) await TraceStore.instance.addSighting(sighting);
    if (addToWatchlist) {
      final watch = await TraceStore.instance.addWatchTarget(
        url,
        label: social?.label,
      );
      await TraceStore.instance.touchWatchTarget(
        watch.id,
        reference: sighting.reference,
      );
    }

    return TraceScanResult(
      sighting: sighting,
      matchedClaim: matched,
      bytes: bytes,
    );
  }

  Future<List<TraceScanResult>> scanWatchlist({ClaimKey? claimKey}) async {
    final targets = await TraceStore.instance.listWatchTargets();
    final out = <TraceScanResult>[];
    for (final target in targets) {
      final result = await scanUrl(
        target.url,
        claimKey: claimKey,
        persist: true,
      );
      await TraceStore.instance.touchWatchTarget(
        target.id,
        reference: result.sighting.reference,
      );
      out.add(result);
    }
    return out;
  }

  static bool _looksLikeHttpUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  static bool _looksLikeDirectMedia(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    return path.endsWith('.png') ||
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.webp') ||
        path.endsWith('.gif') ||
        path.endsWith('.mp4') ||
        path.endsWith('.mov') ||
        path.endsWith('.m4v') ||
        path.endsWith('.wav') ||
        path.endsWith('.pdf');
  }

  static String _id() => 'sight_${DateTime.now().toUtc().microsecondsSinceEpoch}';

  static TraceMedium _detectMedium({
    required String url,
    required String? contentType,
    required Uint8List bytes,
  }) {
    final ct = (contentType ?? '').toLowerCase();
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();

    if (ct.contains('pdf') || path.endsWith('.pdf') || _isPdf(bytes)) {
      return TraceMedium.pdf;
    }
    if (ct.startsWith('image/') ||
        path.endsWith('.png') ||
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.webp') ||
        _isPng(bytes) ||
        _isJpeg(bytes)) {
      return TraceMedium.image;
    }
    if (ct.contains('wav') ||
        ct.contains('audio/wave') ||
        path.endsWith('.wav') ||
        _isWav(bytes)) {
      return TraceMedium.audio;
    }
    if (ct.startsWith('video/') ||
        path.endsWith('.mp4') ||
        path.endsWith('.mov') ||
        path.endsWith('.m4v') ||
        _isMp4(bytes)) {
      return TraceMedium.video;
    }

    // Fallbacks by sniffing when servers omit content-type.
    if (_isPdf(bytes)) return TraceMedium.pdf;
    if (_isPng(bytes) || _isJpeg(bytes)) return TraceMedium.image;
    if (_isWav(bytes)) return TraceMedium.audio;
    if (_isMp4(bytes)) return TraceMedium.video;
    return TraceMedium.unknown;
  }

  static bool _isPdf(Uint8List b) =>
      b.length >= 5 &&
      b[0] == 0x25 &&
      b[1] == 0x50 &&
      b[2] == 0x44 &&
      b[3] == 0x46;

  static bool _isPng(Uint8List b) =>
      b.length >= 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4e &&
      b[3] == 0x47;

  static bool _isJpeg(Uint8List b) =>
      b.length >= 3 && b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff;

  static bool _isWav(Uint8List b) =>
      b.length >= 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x41 &&
      b[10] == 0x56 &&
      b[11] == 0x45;

  static bool _isMp4(Uint8List b) =>
      b.length >= 12 &&
      b[4] == 0x66 &&
      b[5] == 0x74 &&
      b[6] == 0x79 &&
      b[7] == 0x70;

  Future<
      ({
        bool found,
        ClaimStatus status,
        String? owner,
        String? subject,
        String? reference,
      })> _extract(
    TraceMedium medium,
    Uint8List bytes,
    ClaimKey? claimKey,
  ) async {
    try {
      switch (medium) {
        case TraceMedium.image:
          final outcome = await extractWatermark(bytes, claimKey: claimKey);
          final payload = WatermarkPayload.tryParse(outcome.raw);
          final status = outcome.claimStatus;
          return (
            found: payload != null,
            status: status,
            owner: payload?.owner,
            subject: payload?.asset,
            reference: payload?.signature,
          );
        case TraceMedium.audio:
          final outcome =
              await extractAudioWatermark(bytes, claimKey: claimKey);
          final payload = AudioPayload.tryParse(outcome.raw);
          return (
            found: payload != null,
            status: outcome.claimStatus,
            owner: payload?.owner,
            subject: payload?.asset,
            reference: payload?.signature,
          );
        case TraceMedium.pdf:
          final outcome =
              await verifyPdfFingerprint(bytes, claimKey: claimKey);
          return (
            found: outcome.recovered != null,
            status: outcome.claimStatus,
            owner: outcome.recovered?.owner,
            subject: outcome.recovered?.document,
            reference: outcome.recovered?.identifier ??
                outcome.recovered?.signature,
          );
        case TraceMedium.video:
          final outcome =
              await verifyVideoFingerprint(bytes, claimKey: claimKey);
          return (
            found: outcome.recovered != null,
            status: outcome.claimStatus,
            owner: outcome.recovered?.owner,
            subject: outcome.recovered?.document,
            reference: outcome.recovered?.identifier ??
                outcome.recovered?.signature,
          );
        case TraceMedium.unknown:
          // Try image then pdf then audio then video.
          for (final probe in [
            TraceMedium.image,
            TraceMedium.pdf,
            TraceMedium.audio,
            TraceMedium.video,
          ]) {
            final result = await _extract(probe, bytes, claimKey);
            if (result.found) return result;
          }
          return (
            found: false,
            status: ClaimStatus.missing,
            owner: null,
            subject: null,
            reference: null,
          );
      }
    } catch (_) {
      return (
        found: false,
        status: ClaimStatus.missing,
        owner: null,
        subject: null,
        reference: null,
      );
    }
  }
}
