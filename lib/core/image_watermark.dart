/// LSB watermark codec — Dart port of the website's canvas-based codec.
///
/// The bit layout uses a Signata magic header (`SGN1`, 4-byte
/// big-endian length, payload bits spread over the R/G/B least significant
/// bits of each pixel in row-major order), so a PNG watermarked in the app
/// verifies on the website and vice versa.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'fingerprint.dart';

const String _magic = 'SGN1';

/// Payload embedded inside the pixels. Field names match the web prototype.
class WatermarkPayload {
  const WatermarkPayload({
    required this.owner,
    required this.asset,
    required this.issued,
    required this.signature,
  });

  final String owner;
  final String asset;
  final String issued;
  final String signature;

  Map<String, dynamic> toJson() => {
        'owner': owner,
        'asset': asset,
        'issued': issued,
        'signature': signature,
      };

  static WatermarkPayload? tryParse(String? raw) {
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return null;
      return WatermarkPayload(
        owner: map['owner'] as String? ?? '',
        asset: map['asset'] as String? ?? '',
        issued: map['issued'] as String? ?? '',
        signature: map['signature'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// A payload is genuine when its signature matches the fingerprint
  /// recomputed from its own claim fields.
  bool get signatureValid =>
      signature == fingerprint('$owner|$asset|$issued');
}

class EmbedOutcome {
  const EmbedOutcome({
    required this.originalPng,
    required this.markedPng,
    required this.payload,
    required this.width,
    required this.height,
    required this.bitsUsed,
    required this.capacityBits,
    required this.recoveredRaw,
  });

  final Uint8List originalPng;
  final Uint8List markedPng;
  final WatermarkPayload payload;
  final int width;
  final int height;
  final int bitsUsed;
  final int capacityBits;

  /// Raw payload extracted back out of the encoded PNG (round trip).
  final String? recoveredRaw;

  WatermarkPayload? get recovered => WatermarkPayload.tryParse(recoveredRaw);

  bool get verified {
    final r = recovered;
    return r != null &&
        r.owner == payload.owner &&
        r.asset == payload.asset &&
        r.signature == payload.signature;
  }
}

class ExtractOutcome {
  const ExtractOutcome({required this.raw, required this.previewPng});

  final String? raw;
  final Uint8List previewPng;
}

/* ------------------------- bit-level codec ------------------------- */

({int bitsUsed, int capacityBits}) _embedBits(Uint8List rgba, String payload) {
  final body = utf8.encode(payload);
  final header = ascii.encode(_magic);
  final bytes = Uint8List(header.length + 4 + body.length);
  bytes.setAll(0, header);
  bytes[4] = (body.length >>> 24) & 0xff;
  bytes[5] = (body.length >>> 16) & 0xff;
  bytes[6] = (body.length >>> 8) & 0xff;
  bytes[7] = body.length & 0xff;
  bytes.setAll(8, body);

  final capacity = (rgba.length ~/ 4) * 3 ~/ 8;
  if (bytes.length > capacity) {
    throw const ImageTooSmallException();
  }

  var bit = 0;
  final totalBits = bytes.length * 8;
  for (var i = 0; i < rgba.length && bit < totalBits; i += 4) {
    for (var c = 0; c < 3 && bit < totalBits; c++, bit++) {
      final byte = bytes[bit >> 3];
      final value = (byte >> (7 - (bit & 7))) & 1;
      rgba[i + c] = (rgba[i + c] & 0xfe) | value;
    }
  }
  return (bitsUsed: totalBits, capacityBits: capacity * 8);
}

String? _extractBits(Uint8List rgba) {
  Uint8List? readBytes(int count, int startBit) {
    final out = Uint8List(count);
    var bit = startBit;
    for (var b = 0; b < count; b++) {
      var byte = 0;
      for (var k = 0; k < 8; k++, bit++) {
        final pixel = (bit ~/ 3) * 4 + (bit % 3);
        if (pixel >= rgba.length) return null;
        byte = (byte << 1) | (rgba[pixel] & 1);
      }
      out[b] = byte;
    }
    return out;
  }

  final header = readBytes(8, 0);
  if (header == null) return null;
  if (String.fromCharCodes(header.sublist(0, 4)) != _magic) return null;
  final length =
      (header[4] << 24) | (header[5] << 16) | (header[6] << 8) | header[7];
  if (length <= 0 || length > 1000000) return null;
  final body = readBytes(length, 64);
  if (body == null) return null;
  try {
    return utf8.decode(body);
  } catch (_) {
    return null;
  }
}

class ImageTooSmallException implements Exception {
  const ImageTooSmallException();

  @override
  String toString() =>
      'Image is too small to carry this fingerprint. Try a larger image.';
}

/* --------------------------- isolate tasks --------------------------- */

Uint8List _rgbaOf(img.Image source) {
  final converted = source.convert(format: img.Format.uint8, numChannels: 4);
  return converted.getBytes(order: img.ChannelOrder.rgba);
}

EmbedOutcome _embedTask(
    ({Uint8List fileBytes, String owner, String fileName, String issued})
        args) {
  final (:fileBytes, :owner, :fileName, :issued) = args;
  var decoded = img.decodeImage(fileBytes);
  if (decoded == null) {
    throw Exception('Could not decode this image. Try a PNG, JPG or WEBP.');
  }

  // Match the website: bound processing to 900px on the longest edge.
  final maxDim = math.max(decoded.width, decoded.height);
  if (maxDim > 900) {
    final scale = 900 / maxDim;
    decoded = img.copyResize(
      decoded,
      width: math.max(1, (decoded.width * scale).round()),
      height: math.max(1, (decoded.height * scale).round()),
      interpolation: img.Interpolation.average,
    );
  }

  final w = decoded.width;
  final h = decoded.height;
  final rgba = _rgbaOf(decoded);

  final originalPng = img.encodePng(
    img.Image.fromBytes(
      width: w,
      height: h,
      bytes: Uint8List.fromList(rgba).buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    ),
  );

  final resolvedOwner =
      owner.trim().isEmpty ? 'Anonymous creator' : owner.trim();
  final asset = '$fileName\u00b7${w}x$h';
  final payload = WatermarkPayload(
    owner: resolvedOwner,
    asset: asset,
    issued: issued,
    signature: fingerprint('$resolvedOwner|$asset|$issued'),
  );

  final stats = _embedBits(rgba, jsonEncode(payload.toJson()));
  final markedPng = img.encodePng(
    img.Image.fromBytes(
      width: w,
      height: h,
      bytes: rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    ),
  );

  // Round trip: extract from the delivered PNG, exactly as a verifier would.
  final delivered = img.decodePng(markedPng);
  final recovered = delivered == null ? null : _extractBits(_rgbaOf(delivered));

  return EmbedOutcome(
    originalPng: originalPng,
    markedPng: markedPng,
    payload: payload,
    width: w,
    height: h,
    bitsUsed: stats.bitsUsed,
    capacityBits: stats.capacityBits,
    recoveredRaw: recovered,
  );
}

ExtractOutcome _extractTask(Uint8List fileBytes) {
  final decoded = img.decodeImage(fileBytes);
  if (decoded == null) {
    throw Exception('Could not decode this image. Try a PNG, JPG or WEBP.');
  }
  final raw = _extractBits(_rgbaOf(decoded));

  var preview = decoded;
  final maxDim = math.max(decoded.width, decoded.height);
  if (maxDim > 600) {
    final scale = 600 / maxDim;
    preview = img.copyResize(
      decoded,
      width: math.max(1, (decoded.width * scale).round()),
      height: math.max(1, (decoded.height * scale).round()),
    );
  }
  return ExtractOutcome(raw: raw, previewPng: img.encodePng(preview));
}

/// Embeds an ownership payload into the image and round-trip verifies it.
Future<EmbedOutcome> embedWatermark({
  required Uint8List fileBytes,
  required String owner,
  required String fileName,
}) {
  final issued = DateTime.now().toUtc().toIso8601String();
  return compute(_embedTask,
      (fileBytes: fileBytes, owner: owner, fileName: fileName, issued: issued));
}

/// Extracts a watermark payload from any image file, if one is present.
Future<ExtractOutcome> extractWatermark(Uint8List fileBytes) =>
    compute(_extractTask, fileBytes);
