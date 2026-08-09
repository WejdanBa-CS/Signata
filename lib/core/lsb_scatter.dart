/// Seeded bit-position scatter for LSB carriers (image RGB / audio PCM).
library;

import 'dart:typed_data';

/// xorshift32 PRNG for deterministic bit-slot permutation.
class LsbScatter {
  LsbScatter._(this._slots);

  final List<int> _slots;

  /// [slotCount] addressable LSB positions (image: pixels*3, audio: samples).
  factory LsbScatter.seeded({
    required int slotCount,
    required int seed,
  }) {
    final slots = List<int>.generate(slotCount, (i) => i);
    var state = seed == 0 ? 0xA5A5A5A5 : seed;
    int next() {
      state ^= state << 13;
      state &= 0xFFFFFFFF;
      state ^= state >> 17;
      state &= 0xFFFFFFFF;
      state ^= state << 5;
      state &= 0xFFFFFFFF;
      return state;
    }

    for (var i = slots.length - 1; i > 0; i--) {
      final j = next() % (i + 1);
      final tmp = slots[i];
      slots[i] = slots[j];
      slots[j] = tmp;
    }
    return LsbScatter._(slots);
  }

  static int seedFromHeader(Uint8List header8) {
    var h = 0x811c9dc5;
    for (final b in header8) {
      h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF;
    }
    return h == 0 ? 1 : h;
  }

  int get length => _slots.length;

  int operator [](int bitIndex) => _slots[bitIndex];
}
