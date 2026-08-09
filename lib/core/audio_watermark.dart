/// Inaudible WAV LSB watermark — ownership payload encoded into the
/// least-significant bit of each 16-bit PCM sample using scattered placement.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;

import 'claim_crypto.dart';
import 'lsb_scatter.dart';

const String _magic = 'SGA1';

class AudioPayload {
  const AudioPayload({
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

  static AudioPayload? tryParse(String? raw) {
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return null;
      return AudioPayload(
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

class AudioEmbedOutcome {
  const AudioEmbedOutcome({
    required this.markedWav,
    required this.payload,
    required this.sampleRate,
    required this.channels,
    required this.bitsUsed,
    required this.capacityBits,
    required this.recoveredRaw,
    required this.claimStatus,
  });

  final Uint8List markedWav;
  final AudioPayload payload;
  final int sampleRate;
  final int channels;
  final int bitsUsed;
  final int capacityBits;
  final String? recoveredRaw;
  final ClaimStatus claimStatus;

  AudioPayload? get recovered => AudioPayload.tryParse(recoveredRaw);

  bool get verified {
    final r = recovered;
    return r != null &&
        r.owner == payload.owner &&
        r.asset == payload.asset &&
        r.signature == payload.signature;
  }
}

class AudioExtractOutcome {
  const AudioExtractOutcome({
    required this.raw,
    required this.sampleRate,
    required this.channels,
    this.claimStatus = ClaimStatus.missing,
  });

  final String? raw;
  final int sampleRate;
  final int channels;
  final ClaimStatus claimStatus;
}

class NotAWavException implements Exception {
  const NotAWavException(
      [this.message = 'That file is not a valid WAV audio file.']);
  final String message;
  @override
  String toString() => message;
}

class AudioTooShortException implements Exception {
  const AudioTooShortException();
  @override
  String toString() =>
      'Audio is too short to carry this fingerprint. Try a longer clip.';
}

class _WavInfo {
  _WavInfo({
    required this.bytes,
    required this.dataOffset,
    required this.dataSize,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
  });

  final Uint8List bytes;
  final int dataOffset;
  final int dataSize;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
}

_WavInfo _parseWav(Uint8List bytes) {
  if (bytes.length < 44) throw const NotAWavException();
  final riff = String.fromCharCodes(bytes.sublist(0, 4));
  final wave = String.fromCharCodes(bytes.sublist(8, 12));
  if (riff != 'RIFF' || wave != 'WAVE') {
    throw const NotAWavException();
  }

  var offset = 12;
  int? sampleRate;
  int? channels;
  int? bitsPerSample;
  int? dataOffset;
  int? dataSize;

  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = ByteData.sublistView(bytes, offset + 4, offset + 8)
        .getUint32(0, Endian.little);
    final body = offset + 8;
    if (id == 'fmt ' && body + 16 <= bytes.length) {
      final fmt = ByteData.sublistView(bytes, body, body + 16);
      channels = fmt.getUint16(2, Endian.little);
      sampleRate = fmt.getUint32(4, Endian.little);
      bitsPerSample = fmt.getUint16(14, Endian.little);
    } else if (id == 'data') {
      dataOffset = body;
      dataSize = size;
      break;
    }
    offset = body + size + (size.isOdd ? 1 : 0);
  }

  if (sampleRate == null ||
      channels == null ||
      bitsPerSample == null ||
      dataOffset == null ||
      dataSize == null) {
    throw const NotAWavException('WAV is missing fmt/data chunks.');
  }
  if (bitsPerSample != 16) {
    throw const NotAWavException(
      'Prototype supports 16-bit PCM WAV only. Export as WAV 16-bit and try again.',
    );
  }
  if (dataOffset + dataSize > bytes.length) {
    throw const NotAWavException('WAV data chunk is truncated.');
  }

  return _WavInfo(
    bytes: bytes,
    dataOffset: dataOffset,
    dataSize: dataSize,
    sampleRate: sampleRate,
    channels: channels,
    bitsPerSample: bitsPerSample,
  );
}

Uint8List _magicSeedHeader() {
  final header = Uint8List(8);
  header.setAll(0, ascii.encode(_magic));
  return header;
}

Uint8List _buildPacket(String payloadJson) {
  final body = utf8.encode(payloadJson);
  final header = ascii.encode(_magic);
  final headerBlock = Uint8List(8);
  headerBlock.setAll(0, header);
  headerBlock[4] = (body.length >>> 24) & 0xff;
  headerBlock[5] = (body.length >>> 16) & 0xff;
  headerBlock[6] = (body.length >>> 8) & 0xff;
  headerBlock[7] = body.length & 0xff;

  // Packet = header + redundant header + body.
  final packet = Uint8List(16 + body.length);
  packet.setAll(0, headerBlock);
  packet.setAll(8, headerBlock);
  packet.setAll(16, body);
  return packet;
}

void _writeScatteredBit(
  Uint8List pcm,
  LsbScatter scatter,
  int bitIndex,
  int value,
) {
  final sampleIndex = scatter[bitIndex] * 2;
  if (sampleIndex >= pcm.length) return;
  pcm[sampleIndex] = (pcm[sampleIndex] & 0xfe) | (value & 1);
}

int _readScatteredBit(Uint8List pcm, LsbScatter scatter, int bitIndex) {
  final sampleIndex = scatter[bitIndex] * 2;
  if (sampleIndex >= pcm.length) return 0;
  return pcm[sampleIndex] & 1;
}

Uint8List? _readScatteredBytes(
  Uint8List pcm,
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
      byte = (byte << 1) | _readScatteredBit(pcm, scatter, bit);
    }
    out[b] = byte;
  }
  return out;
}

({int bitsUsed, int capacityBits}) _embedScattered(
  Uint8List pcm,
  Uint8List packet,
) {
  final slotCount = pcm.length ~/ 2;
  final scatter = LsbScatter.seeded(
    slotCount: slotCount,
    seed: LsbScatter.seedFromHeader(_magicSeedHeader()),
  );
  final totalBits = packet.length * 8;
  if (totalBits > slotCount) throw const AudioTooShortException();

  for (var bit = 0; bit < totalBits; bit++) {
    final byte = packet[bit >> 3];
    final value = (byte >> (7 - (bit & 7))) & 1;
    _writeScatteredBit(pcm, scatter, bit, value);
  }
  return (bitsUsed: totalBits, capacityBits: slotCount);
}

String? _extractScattered(Uint8List pcm) {
  final slotCount = pcm.length ~/ 2;
  if (slotCount < 128) return null;
  final scatter = LsbScatter.seeded(
    slotCount: slotCount,
    seed: LsbScatter.seedFromHeader(_magicSeedHeader()),
  );

  final header0 = _readScatteredBytes(pcm, scatter, 8, 0);
  final header1 = _readScatteredBytes(pcm, scatter, 8, 64);

  Uint8List? header;
  if (header0 != null &&
      String.fromCharCodes(header0.sublist(0, 4)) == _magic) {
    header = header0;
  } else if (header1 != null &&
      String.fromCharCodes(header1.sublist(0, 4)) == _magic) {
    header = header1;
  } else {
    return null;
  }

  final length =
      (header[4] << 24) | (header[5] << 16) | (header[6] << 8) | header[7];
  if (length <= 0 || length > 1000000) return null;
  if (128 + length * 8 > scatter.length) return null;

  final body = _readScatteredBytes(pcm, scatter, length, 128);
  if (body == null) return null;
  try {
    return utf8.decode(body);
  } catch (_) {
    return null;
  }
}

({int bitsUsed, int capacityBits}) _embedSequential(
  Uint8List pcm,
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

  final capacity = pcm.length ~/ 2;
  final totalBits = bytes.length * 8;
  if (totalBits > capacity) throw const AudioTooShortException();

  var bit = 0;
  for (var i = 0; i < pcm.length && bit < totalBits; i += 2, bit++) {
    final byte = bytes[bit >> 3];
    final value = (byte >> (7 - (bit & 7))) & 1;
    pcm[i] = (pcm[i] & 0xfe) | value;
  }
  return (bitsUsed: totalBits, capacityBits: capacity);
}

String? _extractSequential(Uint8List pcm) {
  Uint8List? readBytes(int count, int startBit) {
    final out = Uint8List(count);
    var bit = startBit;
    for (var b = 0; b < count; b++) {
      var byte = 0;
      for (var k = 0; k < 8; k++, bit++) {
        final sampleIndex = bit * 2;
        if (sampleIndex >= pcm.length) return null;
        byte = (byte << 1) | (pcm[sampleIndex] & 1);
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

String? _extractBits(Uint8List pcm) =>
    _extractScattered(pcm) ?? _extractSequential(pcm);

ClaimKey? _claimKeyFromArgs(Uint8List? keyBytes, String? kid) {
  if (keyBytes == null || keyBytes.length != 32) return null;
  return ClaimKey(bytes: keyBytes, kid: kid ?? ClaimKey.kidFor(keyBytes));
}

AudioPayload _buildPayload({
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
    return AudioPayload(
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
  return AudioPayload(
    owner: resolvedOwner,
    asset: asset,
    issued: issued,
    signature: legacy.signature,
    alg: legacy.alg,
    kid: legacy.kid,
    version: legacy.version,
  );
}

AudioEmbedOutcome _embedTask(
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
  final wav = _parseWav(fileBytes);
  final marked = Uint8List.fromList(fileBytes);
  final pcm = marked.sublist(wav.dataOffset, wav.dataOffset + wav.dataSize);

  final asset =
      '$fileName·${wav.sampleRate}Hz·${wav.channels}ch·${wav.dataSize}B';
  final payload = _buildPayload(
    owner: owner,
    asset: asset,
    issued: issued,
    claimKey: claimKey,
  );

  final packet = _buildPacket(jsonEncode(payload.toJson()));
  final stats = _embedScattered(pcm, packet);
  marked.setRange(wav.dataOffset, wav.dataOffset + wav.dataSize, pcm);

  final recovered = _extractBits(
    marked.sublist(wav.dataOffset, wav.dataOffset + wav.dataSize),
  );
  final recoveredPayload = AudioPayload.tryParse(recovered);
  final claimStatus =
      recoveredPayload?.statusWith(claimKey) ?? ClaimStatus.missing;

  return AudioEmbedOutcome(
    markedWav: marked,
    payload: payload,
    sampleRate: wav.sampleRate,
    channels: wav.channels,
    bitsUsed: stats.bitsUsed,
    capacityBits: stats.capacityBits,
    recoveredRaw: recovered,
    claimStatus: claimStatus,
  );
}

AudioExtractOutcome _extractTask(
  ({Uint8List fileBytes, Uint8List? keyBytes, String? kid}) args,
) {
  final (:fileBytes, :keyBytes, :kid) = args;
  final claimKey = _claimKeyFromArgs(keyBytes, kid);
  final wav = _parseWav(fileBytes);
  final pcm = fileBytes.sublist(wav.dataOffset, wav.dataOffset + wav.dataSize);
  final raw = _extractBits(pcm);
  final payload = AudioPayload.tryParse(raw);
  return AudioExtractOutcome(
    raw: raw,
    sampleRate: wav.sampleRate,
    channels: wav.channels,
    claimStatus: payload?.statusWith(claimKey) ?? ClaimStatus.missing,
  );
}

Future<AudioEmbedOutcome> embedAudioWatermark({
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

Future<AudioExtractOutcome> extractAudioWatermark(
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
