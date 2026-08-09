/// Incoming shares from Instagram, TikTok, X, and the system share sheet.
library;

import 'dart:async';
import 'dart:io';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class SharedIngressFile {
  const SharedIngressFile({
    required this.path,
    required this.fileName,
    this.mimeType,
    this.text,
  });

  final String path;
  final String fileName;
  final String? mimeType;
  final String? text;
}

typedef SharedIngressHandler = void Function(List<SharedIngressFile> files);

/// Listens for media/text shared into Signata from other apps.
class ShareIngress {
  ShareIngress._();
  static final ShareIngress instance = ShareIngress._();

  StreamSubscription<List<SharedMediaFile>>? _sub;
  SharedIngressHandler? _handler;

  void listen(SharedIngressHandler handler) {
    _handler = handler;
    _sub?.cancel();
    _sub = ReceiveSharingIntent.instance.getMediaStream().listen(
      _dispatch,
      onError: (_) {},
    );
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      if (files.isNotEmpty) {
        _dispatch(files);
        ReceiveSharingIntent.instance.reset();
      }
    }).catchError((_) {});
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _handler = null;
  }

  void _dispatch(List<SharedMediaFile> files) {
    final handler = _handler;
    if (handler == null || files.isEmpty) return;
    final mapped = <SharedIngressFile>[];
    for (final file in files) {
      final path = file.path;
      if (path.isEmpty) continue;
      // Text-only shares (a social URL) are represented as path-less / type.text.
      if (file.type == SharedMediaType.text ||
          file.type == SharedMediaType.url) {
        final text = file.path; // package stores text in path for text shares
        if (text.trim().isEmpty) continue;
        mapped.add(SharedIngressFile(
          path: '',
          fileName: 'shared-link.txt',
          mimeType: 'text/plain',
          text: text.trim(),
        ));
        continue;
      }
      mapped.add(SharedIngressFile(
        path: path,
        fileName: path.split(Platform.pathSeparator).last,
        mimeType: file.mimeType,
      ));
    }
    if (mapped.isNotEmpty) handler(mapped);
  }
}
