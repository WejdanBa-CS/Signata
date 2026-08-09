import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Builds adaptive-icon layers:
/// - foreground: fingerprint on transparent canvas, scaled into the safe zone
/// - background: solid EchoMark navy
void main() {
  final source = img.decodeImage(File('assets/icon.png').readAsBytesSync());
  if (source == null) {
    stderr.writeln('Could not decode assets/icon.png');
    exit(1);
  }

  const size = 1024;
  // flutter_launcher_icons already applies a 16% adaptive inset, so keep the
  // mark large in the source and let that inset create the safe zone.
  const contentScale = 0.9;
  final contentSize = (size * contentScale).round();

  // Punch out the near-black source background so only the mark remains.
  final mark = img.Image(width: source.width, height: source.height, numChannels: 4);
  for (final p in source) {
    final luminance = (0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b);
    final isBackground = luminance < 28 && p.r < 40 && p.g < 40 && p.b < 50;
    if (isBackground) {
      mark.setPixelRgba(p.x, p.y, 0, 0, 0, 0);
    } else {
      mark.setPixelRgba(p.x, p.y, p.r, p.g, p.b, 255);
    }
  }

  // Tight crop around opaque pixels, then pad equally.
  var minX = mark.width, minY = mark.height, maxX = 0, maxY = 0;
  for (final p in mark) {
    if (p.a < 16) continue;
    minX = math.min(minX, p.x);
    minY = math.min(minY, p.y);
    maxX = math.max(maxX, p.x);
    maxY = math.max(maxY, p.y);
  }
  final cropped = img.copyCrop(
    mark,
    x: minX,
    y: minY,
    width: maxX - minX + 1,
    height: maxY - minY + 1,
  );

  final resized = img.copyResize(
    cropped,
    width: contentSize,
    height: contentSize,
    interpolation: img.Interpolation.average,
  );

  final foreground = img.Image(width: size, height: size, numChannels: 4);
  img.fill(foreground, color: img.ColorRgba8(0, 0, 0, 0));
  final offset = ((size - contentSize) / 2).round();
  img.compositeImage(foreground, resized, dstX: offset, dstY: offset);

  // Legacy / iOS fallback: same mark on solid navy.
  final legacy = img.Image(width: size, height: size);
  img.fill(legacy, color: img.ColorRgba8(3, 12, 20, 255));
  img.compositeImage(legacy, resized, dstX: offset, dstY: offset);

  File('assets/icon_foreground.png').writeAsBytesSync(img.encodePng(foreground));
  File('assets/icon_padded.png').writeAsBytesSync(img.encodePng(legacy));

  stdout.writeln('Wrote assets/icon_foreground.png and assets/icon_padded.png');
}
