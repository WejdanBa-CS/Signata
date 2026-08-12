/// Incoming shares from Instagram, TikTok, X, and the system share sheet.
///
/// [start] begins listening early (before login). Shares are buffered until
/// [attach] delivers them to [AppShell] / Trace after the user is ready.
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
  final List<SharedIngressFile> _buffer = [];
  bool _started = false;
  bool _initialConsumed = false;

  /// Call once from [main] so cold-start shares survive login / email activate.
  void start() {
    if (_started) return;
    _started = true;
    _sub?.cancel();
    _sub = ReceiveSharingIntent.instance.getMediaStream().listen(
      _onRaw,
      onError: (_) {},
    );
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      if (files.isEmpty) return;
      _onRaw(files);
    }).catchError((_) {});
  }

  void attach(SharedIngressHandler handler) {
    _handler = handler;
    if (_buffer.isEmpty) return;
    final pending = List<SharedIngressFile>.from(_buffer);
    _buffer.clear();
    _deliver(pending);
  }

  void detach() {
    _handler = null;
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _handler = null;
    _buffer.clear();
    _started = false;
    _initialConsumed = false;
  }

  void _onRaw(List<SharedMediaFile> files) {
    final mapped = _map(files);
    if (mapped.isEmpty) return;
    if (_handler != null) {
      _deliver(mapped);
    } else {
      _buffer
        ..clear()
        ..addAll(mapped);
    }
  }

  void _deliver(List<SharedIngressFile> files) {
    final handler = _handler;
    if (handler == null || files.isEmpty) return;
    handler(files);
    if (!_initialConsumed) {
      _initialConsumed = true;
      try {
        ReceiveSharingIntent.instance.reset();
      } catch (_) {}
    }
  }

  List<SharedIngressFile> _map(List<SharedMediaFile> files) {
    final mapped = <SharedIngressFile>[];
    for (final file in files) {
      final path = file.path;
      if (path.isEmpty) continue;
      if (file.type == SharedMediaType.text ||
          file.type == SharedMediaType.url) {
        final text = file.path;
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
    return mapped;
  }
}
