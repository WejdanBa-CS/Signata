import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'social_platforms.dart';
import 'social_protect.dart';

/// Writes [bytes] to a temp file and opens the native share sheet, letting
/// the user save to Files, AirDrop, message, etc.
Future<void> shareBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  String? text,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: mimeType)],
      text: text,
    ),
  );
}

/// Shares one or more fingerprinted social assets, then optionally opens the
/// target app (Instagram / TikTok / X) so the user can finish posting.
Future<void> shareProtectedToSocial({
  required SocialPlatformInfo platform,
  required List<SocialProtectItem> items,
  String? caption,
  bool openAppAfterShare = true,
}) async {
  if (items.isEmpty) return;
  final dir = await getTemporaryDirectory();
  final files = <XFile>[];
  for (final item in items) {
    final path =
        '${dir.path}${Platform.pathSeparator}signata-${platform.shortLabel}-${item.fileName}';
    final file = File(path);
    await file.writeAsBytes(item.bytes, flush: true);
    files.add(XFile(file.path, mimeType: item.mimeType, name: item.fileName));
  }

  await SharePlus.instance.share(
    ShareParams(
      files: files,
      text: caption ??
          'Protected with Signata · ready for ${platform.label}',
      subject: 'Signata · ${platform.label}',
    ),
  );

  if (openAppAfterShare) {
    try {
      await platform.openApp();
    } catch (_) {}
  }
}

/// Saves [bytes] via the native save/download dialog.
///
/// Falls back to the Downloads (or app Documents) folder if the dialog is
/// unavailable. Returns the saved file path.
Future<String> downloadBytes({
  required Uint8List bytes,
  required String fileName,
  String? dialogTitle,
  List<String>? allowedExtensions,
}) async {
  final ext = _extensionOf(fileName);

  try {
    final path = await FilePicker.saveFile(
      dialogTitle: dialogTitle ?? 'Download fingerprinted file',
      fileName: fileName,
      type: ext == null ? FileType.any : FileType.custom,
      allowedExtensions: ext == null ? null : (allowedExtensions ?? [ext]),
      bytes: bytes,
    );
    if (path != null && path.isNotEmpty) {
      return path;
    }
  } catch (_) {
    // Fall through to a direct Downloads/Documents write.
  }

  final dir = await getDownloadsDirectory() ??
      await getApplicationDocumentsDirectory();
  await dir.create(recursive: true);
  var target = File('${dir.path}${Platform.pathSeparator}$fileName');
  if (await target.exists()) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final base = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;
    final suffix = ext == null ? '' : '.$ext';
    target = File(
      '${dir.path}${Platform.pathSeparator}$base-$stamp$suffix',
    );
  }
  await target.writeAsBytes(bytes, flush: true);
  return target.path;
}

String? _extensionOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0 || dot == fileName.length - 1) return null;
  return fileName.substring(dot + 1).toLowerCase();
}
