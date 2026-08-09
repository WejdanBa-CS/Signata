/// Inaudible WAV LSB watermark — same ownership payload shape as the image
/// demo, encoded into the least-significant bit of each 16-bit PCM sample.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;

import 'fingerprint.dart';

const String _magic = 'EMA1';

class AudioPayload {
  const AudioPayload({
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
      );
    } catch (_) {
      return null;
    }
  }

  bool get signatureValid =>
      signature == fingerprint('$owner|$asset|$issued');
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
  });

  final Uint8List markedWav;
  final AudioPayload payload;
  final int sampleRate;
  final int channels;
  final int bitsUsed;
  final int capacityBits;
  final String? recoveredRaw;

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
  });

  final String? raw;
  final int sampleRate;
  final int channels;
}

class NotAWavException implements Exception {
  const NotAWavException([this.message = 'That file is not a valid WAV audio file.']);
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

({int bitsUsed, int capacityBits}) _embedBits(Uint8List pcm, String payload) {
  final body = utf8.encode(payload);
  final header = ascii.encode(_magic);
  final bytes = Uint8List(header.length + 4 + body.length);
  bytes.setAll(0, header);
  bytes[4] = (body.length >>> 24) & 0xff;
  bytes[5] = (body.length >>> 16) & 0xff;
  bytes[6] = (body.length >>> 8) & 0xff;
  bytes[7] = body.length & 0xff;
  bytes.setAll(8, body);

  // One bit per 16-bit sample (LSB of the low byte).
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

String? _extractBits(Uint8List pcm) {
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

AudioEmbedOutcome _embedTask(
    ({Uint8List fileBytes, String owner, String fileName, String issued})
        args) {
  final (:fileBytes, :owner, :fileName, :issued) = args;
  final wav = _parseWav(fileBytes);
  final marked = Uint8List.fromList(fileBytes);
  final pcm = marked.sublist(wav.dataOffset, wav.dataOffset + wav.dataSize);

  final resolvedOwner =
      owner.trim().isEmpty ? 'Anonymous creator' : owner.trim();
  final asset =
      '$fileName·${wav.sampleRate}Hz·${wav.channels}ch·${wav.dataSize}B';
  final payload = AudioPayload(
    owner: resolvedOwner,
    asset: asset,
    issued: issued,
    signature: fingerprint('$resolvedOwner|$asset|$issued'),
  );

  final stats = _embedBits(pcm, jsonEncode(payload.toJson()));
  marked.setRange(wav.dataOffset, wav.dataOffset + wav.dataSize, pcm);

  final recovered = _extractBits(
    marked.sublist(wav.dataOffset, wav.dataOffset + wav.dataSize),
  );

  return AudioEmbedOutcome(
    markedWav: marked,
    payload: payload,
    sampleRate: wav.sampleRate,
    channels: wav.channels,
    bitsUsed: stats.bitsUsed,
    capacityBits: stats.capacityBits,
    recoveredRaw: recovered,
  );
}

AudioExtractOutcome _extractTask(Uint8List fileBytes) {
  final wav = _parseWav(fileBytes);
  final pcm = fileBytes.sublist(wav.dataOffset, wav.dataOffset + wav.dataSize);
  return AudioExtractOutcome(
    raw: _extractBits(pcm),
    sampleRate: wav.sampleRate,
    channels: wav.channels,
  );
}

Future<AudioEmbedOutcome> embedAudioWatermark({
  required Uint8List fileBytes,
  required String owner,
  required String fileName,
}) {
  final issued = DateTime.now().toUtc().toIso8601String();
  return compute(_embedTask,
      (fileBytes: fileBytes, owner: owner, fileName: fileName, issued: issued));
}

Future<AudioExtractOutcome> extractAudioWatermark(Uint8List fileBytes) =>
    compute(_extractTask, fileBytes);
