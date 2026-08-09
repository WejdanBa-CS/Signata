/// LSB watermark codec — Dart port of the website's canvas-based codec.
///
/// Scattered LSB embedding (seeded from the magic header) with sequential
/// legacy fallback on extract. Payloads may carry HMAC claim signatures
/// (`alg: hmac-sha256`) or legacy FNV self-consistent signatures.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'claim_crypto.dart';
import 'lsb_scatter.dart';

const String _magic = 'SGN1';

/// Payload embedded inside the pixels. Field names match the web prototype.
class WatermarkPayload {
  const WatermarkPayload({
    required this.owner,
    required this.asset,
    required this.issued,
    required this.signature,
    this.alg,
    this.kid,
    this.version = 1,
  });

  final String owner;
  final String asset;
  final String issued;
  final String signature;
  final String? alg;
  final String? kid;
  final int version;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'owner': owner,
      'asset': asset,
      'issued': issued,
      'signature': signature,
    };
    if (alg != null && alg!.isNotEmpty) map['alg'] = alg;
    if (kid != null && kid!.isNotEmpty) map['kid'] = kid;
    if (version > 1) map['v'] = version;
    return map;
  }

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
        alg: map['alg'] as String?,
        kid: map['kid'] as String?,
        version: (map['v'] as num?)?.toInt() ?? 1,
      );
    } catch (_) {
      return null;
    }
  }

  /// Legacy FNV self-consistency (ignores HMAC alg).
  bool get signatureValid {
    final legacy = ClaimCrypto.signMediaLegacy(
      owner: owner,
      asset: asset,
      issued: issued,
    );
    return signature == legacy.signature;
  }

  bool get isAuthentic =>
      statusWith(null) == ClaimStatus.authenticated;

  ClaimStatus statusWith(ClaimKey? key) => ClaimCrypto.evaluateMedia(
        owner: owner,
        asset: asset,
        issued: issued,
        signature: signature,
        alg: alg,
        kid: kid,
        key: key,
      );
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
    required this.resized,
    required this.claimStatus,
  });

  final Uint8List originalPng;
  final Uint8List markedPng;
  final WatermarkPayload payload;
  final int width;
  final int height;
  final int bitsUsed;
  final int capacityBits;
  final String? recoveredRaw;
  final bool resized;
  final ClaimStatus claimStatus;

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
  const ExtractOutcome({
    required this.raw,
    required this.previewPng,
    this.claimStatus = ClaimStatus.missing,
  });

  final String? raw;
  final Uint8List previewPng;
  final ClaimStatus claimStatus;
}

class ImageTooSmallException implements Exception {
  const ImageTooSmallException();

  @override
  String toString() =>
      'Image is too small to carry this fingerprint. Try a larger image.';
}

/* ------------------------- bit-level codec ------------------------- */

Uint8List _magicSeedHeader() {
  final header = Uint8List(8);
  header.setAll(0, ascii.encode(_magic));
  return header;
}

int _rgbaSlotCount(int rgbaLength) => (rgbaLength ~/ 4) * 3;

void _writeScatteredBit(
  Uint8List rgba,
  LsbScatter scatter,
  int bitIndex,
  int value,
) {
  final slot = scatter[bitIndex];
  final pixel = (slot ~/ 3) * 4 + (slot % 3);
  if (pixel >= rgba.length) return;
  rgba[pixel] = (rgba[pixel] & 0xfe) | (value & 1);
}

int _readScatteredBit(Uint8List rgba, LsbScatter scatter, int bitIndex) {
  final slot = scatter[bitIndex];
  final pixel = (slot ~/ 3) * 4 + (slot % 3);
  if (pixel >= rgba.length) return 0;
  return rgba[pixel] & 1;
}

Uint8List? _readScatteredBytes(
  Uint8List rgba,
  LsbScatter scatter,
  int count,
  int startBit,
) {
  final out = Uint8List(count);
  for (var b = 0; b < count; b++) {
    var byte = 0;
    for (var k = 0; k < 8; k++) {
      final bit = startBit + b * 8 + k;
      if (bit >= scatter.length) return null;
      byte = (byte << 1) | _readScatteredBit(rgba, scatter, bit);
    }
    out[b] = byte;
  }
  return out;
}

({int bitsUsed, int capacityBits}) _embedScattered(
  Uint8List rgba,
  Uint8List packet,
) {
  final slotCount = _rgbaSlotCount(rgba.length);
  final scatter = LsbScatter.seeded(
    slotCount: slotCount,
    seed: LsbScatter.seedFromHeader(_magicSeedHeader()),
  );
  final totalBits = packet.length * 8;
  if (totalBits > slotCount) throw const ImageTooSmallException();

  for (var bit = 0; bit < totalBits; bit++) {
    final byte = packet[bit >> 3];
    final value = (byte >> (7 - (bit & 7))) & 1;
    _writeScatteredBit(rgba, scatter, bit, value);
  }
  return (bitsUsed: totalBits, capacityBits: slotCount);
}

String? _extractScattered(Uint8List rgba) {
  final slotCount = _rgbaSlotCount(rgba.length);
  if (slotCount < 64) return null;
  final scatter = LsbScatter.seeded(
    slotCount: slotCount,
    seed: LsbScatter.seedFromHeader(_magicSeedHeader()),
  );

  final header = _readScatteredBytes(rgba, scatter, 8, 0);
  if (header == null) return null;
  if (String.fromCharCodes(header.sublist(0, 4)) != _magic) return null;
  final length =
      (header[4] << 24) | (header[5] << 16) | (header[6] << 8) | header[7];
  if (length <= 0 || length > 1000000) return null;
  final bodyStartBit = 64;
  if (bodyStartBit + length * 8 > scatter.length) return null;
  final body = _readScatteredBytes(rgba, scatter, length, bodyStartBit);
  if (body == null) return null;
  try {
    return utf8.decode(body);
  } catch (_) {
    return null;
  }
}

({int bitsUsed, int capacityBits}) _embedSequential(
  Uint8List rgba,
  String payload,
) {
  final body = utf8.encode(payload);
  final header = ascii.encode(_magic);
  final bytes = Uint8List(header.length + 4 + body.length);
  bytes.setAll(0, header);
  bytes[4] = (body.length >>> 24) & 0xff;
  bytes[5] = (body.length >>> 16) & 0xff;
  bytes[6] = (body.length >>> 8) & 0xff;
  bytes[7] = body.length & 0xff;
  bytes.setAll(8, body);

  final capacity = _rgbaSlotCount(rgba.length);
  final totalBits = bytes.length * 8;
  if (bytes.length > capacity ~/ 8) throw const ImageTooSmallException();

  var bit = 0;
  for (var i = 0; i < rgba.length && bit < totalBits; i += 4) {
    for (var c = 0; c < 3 && bit < totalBits; c++, bit++) {
      final byte = bytes[bit >> 3];
      final value = (byte >> (7 - (bit & 7))) & 1;
      rgba[i + c] = (rgba[i + c] & 0xfe) | value;
    }
  }
  return (bitsUsed: totalBits, capacityBits: capacity);
}

String? _extractSequential(Uint8List rgba) {
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

String? _extractBits(Uint8List rgba) =>
    _extractScattered(rgba) ?? _extractSequential(rgba);

Uint8List _buildPacket(String payloadJson) {
  final body = utf8.encode(payloadJson);
  final header = ascii.encode(_magic);
  final bytes = Uint8List(header.length + 4 + body.length);
  bytes.setAll(0, header);
  bytes[4] = (body.length >>> 24) & 0xff;
  bytes[5] = (body.length >>> 16) & 0xff;
  bytes[6] = (body.length >>> 8) & 0xff;
  bytes[7] = body.length & 0xff;
  bytes.setAll(8, body);
  return bytes;
}

bool _canEmbedScattered(Uint8List rgba, int packetBytes) {
  return packetBytes * 8 <= _rgbaSlotCount(rgba.length);
}

/* --------------------------- isolate tasks --------------------------- */

Uint8List _rgbaOf(img.Image source) {
  final converted = source.convert(format: img.Format.uint8, numChannels: 4);
  return converted.getBytes(order: img.ChannelOrder.rgba);
}

ClaimKey? _claimKeyFromArgs(Uint8List? keyBytes, String? kid) {
  if (keyBytes == null || keyBytes.length != 32) return null;
  return ClaimKey(bytes: keyBytes, kid: kid ?? ClaimKey.kidFor(keyBytes));
}

WatermarkPayload _buildPayload({
  required String owner,
  required String asset,
  required String issued,
  ClaimKey? claimKey,
}) {
  final resolvedOwner =
      owner.trim().isEmpty ? 'Anonymous creator' : owner.trim();
  if (claimKey != null) {
    final signed = ClaimCrypto.signMedia(
      claimKey,
      owner: resolvedOwner,
      asset: asset,
      issued: issued,
    );
    return WatermarkPayload(
      owner: resolvedOwner,
      asset: asset,
      issued: issued,
      signature: signed.signature,
      alg: signed.alg,
      kid: signed.kid,
      version: signed.version,
    );
  }
  final legacy = ClaimCrypto.signMediaLegacy(
    owner: resolvedOwner,
    asset: asset,
    issued: issued,
  );
  return WatermarkPayload(
    owner: resolvedOwner,
    asset: asset,
    issued: issued,
    signature: legacy.signature,
    alg: legacy.alg,
    kid: legacy.kid,
    version: legacy.version,
  );
}

EmbedOutcome _embedTask(
  ({
    Uint8List fileBytes,
    String owner,
    String fileName,
    String issued,
    Uint8List? keyBytes,
    String? kid,
  }) args,
) {
  final (:fileBytes, :owner, :fileName, :issued, :keyBytes, :kid) = args;
  final claimKey = _claimKeyFromArgs(keyBytes, kid);

  var decoded = img.decodeImage(fileBytes);
  if (decoded == null) {
    throw Exception('Could not decode this image. Try a PNG, JPG or WEBP.');
  }

  var resized = false;
  img.Image working = decoded;

  String assetFor(img.Image image) =>
      '$fileName\u00b7${image.width}x${image.height}';

  // Probe payload size at native resolution; resize only if capacity is insufficient.
  var probePayload = _buildPayload(
    owner: owner,
    asset: assetFor(working),
    issued: issued,
    claimKey: claimKey,
  );
  var probePacket = _buildPacket(jsonEncode(probePayload.toJson()));
  var probeRgba = _rgbaOf(working);

  if (!_canEmbedScattered(probeRgba, probePacket.length)) {
    final maxDim = math.max(working.width, working.height);
    if (maxDim > 900) {
      final scale = 900 / maxDim;
      working = img.copyResize(
        working,
        width: math.max(1, (working.width * scale).round()),
        height: math.max(1, (working.height * scale).round()),
        interpolation: img.Interpolation.average,
      );
      resized = true;
      probePayload = _buildPayload(
        owner: owner,
        asset: assetFor(working),
        issued: issued,
        claimKey: claimKey,
      );
      probePacket = _buildPacket(jsonEncode(probePayload.toJson()));
      probeRgba = _rgbaOf(working);
    }
    if (!_canEmbedScattered(probeRgba, probePacket.length)) {
      throw const ImageTooSmallException();
    }
  }

  final w = working.width;
  final h = working.height;
  final rgba = probeRgba;

  final originalPng = img.encodePng(
    img.Image.fromBytes(
      width: w,
      height: h,
      bytes: Uint8List.fromList(rgba).buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    ),
  );

  final payload = probePayload;
  final packet = _buildPacket(jsonEncode(payload.toJson()));
  final stats = _embedScattered(rgba, packet);

  final markedPng = img.encodePng(
    img.Image.fromBytes(
      width: w,
      height: h,
      bytes: rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    ),
  );

  final delivered = img.decodePng(markedPng);
  final recovered =
      delivered == null ? null : _extractBits(_rgbaOf(delivered));

  final recoveredPayload = WatermarkPayload.tryParse(recovered);
  final claimStatus = recoveredPayload?.statusWith(claimKey) ??
      ClaimStatus.missing;

  return EmbedOutcome(
    originalPng: originalPng,
    markedPng: markedPng,
    payload: payload,
    width: w,
    height: h,
    bitsUsed: stats.bitsUsed,
    capacityBits: stats.capacityBits,
    recoveredRaw: recovered,
    resized: resized,
    claimStatus: claimStatus,
  );
}

ExtractOutcome _extractTask(
  ({Uint8List fileBytes, Uint8List? keyBytes, String? kid}) args,
) {
  final (:fileBytes, :keyBytes, :kid) = args;
  final claimKey = _claimKeyFromArgs(keyBytes, kid);

  final decoded = img.decodeImage(fileBytes);
  if (decoded == null) {
    throw Exception('Could not decode this image. Try a PNG, JPG or WEBP.');
  }
  final raw = _extractBits(_rgbaOf(decoded));
  final payload = WatermarkPayload.tryParse(raw);
  final claimStatus =
      payload?.statusWith(claimKey) ?? ClaimStatus.missing;

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
  return ExtractOutcome(
    raw: raw,
    previewPng: img.encodePng(preview),
    claimStatus: claimStatus,
  );
}

/// Embeds an ownership payload into the image and round-trip verifies it.
Future<EmbedOutcome> embedWatermark({
  required Uint8List fileBytes,
  required String owner,
  required String fileName,
  ClaimKey? claimKey,
}) {
  final issued = DateTime.now().toUtc().toIso8601String();
  return compute(
    _embedTask,
    (
      fileBytes: fileBytes,
      owner: owner,
      fileName: fileName,
      issued: issued,
      keyBytes: claimKey?.bytes,
      kid: claimKey?.kid,
    ),
  );
}

/// Extracts a watermark payload from any image file, if one is present.
Future<ExtractOutcome> extractWatermark(
  Uint8List fileBytes, {
  ClaimKey? claimKey,
}) =>
    compute(
      _extractTask,
      (
        fileBytes: fileBytes,
        keyBytes: claimKey?.bytes,
        kid: claimKey?.kid,
      ),
    );
