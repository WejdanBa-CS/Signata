/// Batch-fingerprint media destined for Instagram, TikTok, or X.
library;

import 'dart:typed_data';

import 'audio_watermark.dart';
import 'claim_crypto.dart';
import 'claim_publisher.dart';
import 'claim_status_ui.dart';
import 'history.dart';
import 'image_watermark.dart';
import 'trace_models.dart';
import 'video_fingerprint.dart';

class SocialProtectItem {
  const SocialProtectItem({
    required this.fileName,
    required this.bytes,
    required this.mimeType,
    required this.medium,
    required this.reference,
    required this.owner,
    required this.subject,
    required this.claimStatus,
  });

  final String fileName;
  final Uint8List bytes;
  final String mimeType;
  final TraceMedium medium;
  final String reference;
  final String owner;
  final String subject;
  final ClaimStatus claimStatus;
}

class SocialProtectService {
  SocialProtectService._();
  static final SocialProtectService instance = SocialProtectService._();

  Future<List<SocialProtectItem>> protectMany({
    required List<({String name, Uint8List bytes})> files,
    required String owner,
    bool publishClaims = true,
  }) async {
    final claimKey = await AccountClaimKeys.current();
    final out = <SocialProtectItem>[];

    for (final file in files) {
      final medium = _detectMedium(file.name, file.bytes);
      if (medium == TraceMedium.unknown || medium == TraceMedium.pdf) {
        throw Exception(
          'Unsupported file for social posting: ${file.name}. '
          'Use an image, video, or WAV audio clip.',
        );
      }

      late final SocialProtectItem item;
      switch (medium) {
        case TraceMedium.image:
          final outcome = await embedWatermark(
            fileBytes: file.bytes,
            owner: owner,
            fileName: file.name,
            claimKey: claimKey,
          );
          item = SocialProtectItem(
            fileName: _withExt(file.name, 'png'),
            bytes: outcome.markedPng,
            mimeType: 'image/png',
            medium: TraceMedium.image,
            reference: outcome.payload.signature,
            owner: outcome.payload.owner,
            subject: outcome.payload.asset,
            claimStatus: outcome.claimStatus,
          );
        case TraceMedium.video:
          final outcome = await embedVideoFingerprint(
            source: file.bytes,
            owner: owner,
            fileName: file.name,
            claimKey: claimKey,
          );
          item = SocialProtectItem(
            fileName: file.name,
            bytes: outcome.markedBytes,
            mimeType: 'video/mp4',
            medium: TraceMedium.video,
            reference: outcome.payload.structuralIdentifier(),
            owner: outcome.payload.owner,
            subject: outcome.payload.document,
            claimStatus: outcome.claimStatus,
          );
        case TraceMedium.audio:
          final outcome = await embedAudioWatermark(
            fileBytes: file.bytes,
            owner: owner,
            fileName: file.name,
            claimKey: claimKey,
          );
          item = SocialProtectItem(
            fileName: _withExt(file.name, 'wav'),
            bytes: outcome.markedWav,
            mimeType: 'audio/wav',
            medium: TraceMedium.audio,
            reference: outcome.payload.signature,
            owner: outcome.payload.owner,
            subject: outcome.payload.asset,
            claimStatus: outcome.claimStatus,
          );
        case TraceMedium.pdf:
        case TraceMedium.unknown:
          throw StateError('unreachable');
      }

      out.add(item);
      await HistoryStore.add(HistoryEntry(
        medium: item.medium.wire,
        action: 'embed',
        subject: item.fileName,
        owner: item.owner,
        verified: claimCountsAsVerified(item.claimStatus),
        reference: item.reference,
        at: DateTime.now(),
      ));

      if (publishClaims) {
        try {
          await ClaimPublisher.publishProtected(
            medium: item.medium,
            owner: item.owner,
            subject: item.subject,
            reference: item.reference,
            issued: DateTime.now().toUtc().toIso8601String(),
            alg: claimKey == null ? null : 'hmac-sha256',
            kid: claimKey?.kid,
            note: 'Protected for social posting',
          );
        } catch (_) {
          // Local protect still succeeds even if publish fails.
        }
      }
    }

    return out;
  }

  static TraceMedium _detectMedium(String name, Uint8List bytes) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        _isPng(bytes) ||
        _isJpeg(bytes)) {
      return TraceMedium.image;
    }
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        _isMp4(bytes)) {
      return TraceMedium.video;
    }
    if (lower.endsWith('.wav') || _isWav(bytes)) {
      return TraceMedium.audio;
    }
    return TraceMedium.unknown;
  }

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

  static String _withExt(String name, String ext) {
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    return '$base.$ext';
  }
}
