import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/claim_crypto.dart';
import '../core/claim_status_ui.dart';
import '../core/history.dart';
import '../core/report.dart';
import '../core/share_utils.dart';
import '../core/trace_models.dart';
import '../core/video_fingerprint.dart';
import '../theme.dart';
import '../widgets/em_widgets.dart';
import '../widgets/publish_claim_button.dart';

enum VideoMode { embed, verify }

class VideoToolScreen extends StatefulWidget {
  const VideoToolScreen({super.key, this.defaultOwner = ''});

  final String defaultOwner;

  @override
  State<VideoToolScreen> createState() => _VideoToolScreenState();
}

class _VideoToolScreenState extends State<VideoToolScreen> {
  late final _ownerController =
      TextEditingController(text: widget.defaultOwner);

  VideoMode _mode = VideoMode.embed;
  String? _workingStep;
  String? _error;
  String? _fileName;
  int _elapsedMs = 0;
  String? _reportStatus;

  VideoEmbedOutcome? _embedOutcome;
  VideoVerifyOutcome? _verifyOutcome;

  @override
  void dispose() {
    _ownerController.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _workingStep = null;
      _error = null;
      _embedOutcome = null;
      _verifyOutcome = null;
      _reportStatus = null;
      _elapsedMs = 0;
    });
  }

  Future<void> _pickAndRun() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp4', 'mov', 'm4v'],
    );
    final file = picked?.files.firstOrNull;
    if (file == null) return;
    final bytes = await file.readAsBytes();

    _reset();
    setState(() => _fileName = file.name);
    final stopwatch = Stopwatch()..start();

    try {
      final claimKey = await AccountClaimKeys.current();
      if (_mode == VideoMode.embed) {
        setState(() => _workingStep = 'Profiling container structure');
        final outcome = await embedVideoFingerprint(
          source: bytes,
          owner: _ownerController.text,
          fileName: file.name,
          claimKey: claimKey,
        );
        stopwatch.stop();
        if (!mounted) return;
        setState(() {
          _embedOutcome = outcome;
          _workingStep = null;
          _elapsedMs = stopwatch.elapsedMilliseconds;
        });
        await HistoryStore.add(HistoryEntry(
          medium: 'video',
          action: 'embed',
          subject: file.name,
          owner: outcome.payload.owner,
          verified: claimCountsAsVerified(outcome.claimStatus),
          reference: outcome.payload.identifier,
          at: DateTime.now(),
        ));
      } else {
        setState(() => _workingStep = 'Extracting & verifying');
        final outcome = await verifyVideoFingerprint(bytes, claimKey: claimKey);
        stopwatch.stop();
        if (!mounted) return;
        setState(() {
          _verifyOutcome = outcome;
          _workingStep = null;
          _elapsedMs = stopwatch.elapsedMilliseconds;
        });
        await HistoryStore.add(HistoryEntry(
          medium: 'video',
          action: 'verify',
          subject: file.name,
          owner: outcome.recovered?.owner ?? 'Unknown',
          verified: claimCountsAsVerified(outcome.claimStatus),
          reference: outcome.recovered?.identifier ?? '—',
          at: DateTime.now(),
        ));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _workingStep = null;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _shareMarked() async {
    final outcome = _embedOutcome;
    if (outcome == null) return;
    await shareBytes(
      bytes: outcome.markedBytes,
      fileName: 'signata-${_fileName ?? 'video.mp4'}',
      mimeType: 'video/mp4',
      text: 'Fingerprinted with Signata',
    );
  }

  Future<void> _downloadMarked() async {
    final outcome = _embedOutcome;
    if (outcome == null) return;
    try {
      final path = await downloadBytes(
        bytes: outcome.markedBytes,
        fileName: 'signata-${_fileName ?? 'video.mp4'}',
        dialogTitle: 'Download fingerprinted video',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to $path')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    }
  }

  Future<void> _exportReport() async {
    final outcome = _embedOutcome;
    if (outcome == null) return;
    setState(() => _reportStatus = 'Sealing…');
    try {
      final sealed = sealReport(ReportBody(
        medium: 'video',
        subject: outcome.recovered?.document ?? _fileName ?? 'video.mp4',
        owner: outcome.recovered?.owner ?? 'Unknown',
        verified: claimCountsAsVerified(outcome.claimStatus),
        issued: outcome.payload.issued,
        generated: DateTime.now().toUtc().toIso8601String(),
        evidence: {
          'method': 'Container SHA-256 fingerprint',
          'structuralId': outcome.recovered?.identifier,
          'recomputedId': outcome.recheckId,
          'structureMatch': outcome.structureMatch,
          'structure': outcome.recovered?.structure.toJson(),
          'roundTripMs': _elapsedMs,
        },
      ));
      if (!verifySealedReport(sealed)) {
        throw Exception('Seal self-check failed.');
      }
      await shareBytes(
        bytes: Uint8List.fromList(sealed.toPrettyJson().codeUnits),
        fileName: reportFileName(_fileName ?? 'video.mp4'),
        mimeType: 'application/json',
      );
      setState(() => _reportStatus = 'Sealed · ${sealed.fingerprint}');
    } catch (error) {
      setState(() =>
          _reportStatus = error.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final structure = _mode == VideoMode.embed
        ? _embedOutcome?.recovered?.structure
        : _verifyOutcome?.recovered?.structure;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      children: [
        const SectionHeading(
          tag: 'Video fingerprinting',
          title: 'Bind ownership to a video container',
          desc:
              'Signata profiles the MP4/MOV atom graph — brand, moov/mdat layout, audio/video tracks — derives a SHA-256 identifier, then hides it in the delivered file.',
        ),
        const SizedBox(height: 20),
        SegmentedButton<VideoMode>(
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: EmColors.accent,
            selectedForegroundColor: EmColors.accentForeground,
          ),
          segments: const [
            ButtonSegment(
              value: VideoMode.embed,
              label: Text('Protect'),
              icon: Icon(Icons.fingerprint, size: 18),
            ),
            ButtonSegment(
              value: VideoMode.verify,
              label: Text('Verify a file'),
              icon: Icon(Icons.verified_outlined, size: 18),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (selection) {
            setState(() => _mode = selection.first);
            _reset();
          },
        ),
        const SizedBox(height: 20),
        EmCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_mode == VideoMode.embed) ...[
                const MonoLabel('Ownership claim'),
                const SizedBox(height: 10),
                TextField(
                  controller: _ownerController,
                  decoration: const InputDecoration(
                    hintText: 'Creator or studio name',
                  ),
                ),
                const SizedBox(height: 16),
              ],
              UploadBox(
                icon: Icons.movie_outlined,
                title: _mode == VideoMode.embed
                    ? 'Choose a video to fingerprint'
                    : 'Choose a video to check',
                hint: 'MP4 / MOV / M4V — processed locally',
                buttonLabel: 'Choose video',
                onPick: _pickAndRun,
                fileName: _fileName,
                tone: EmColors.accent,
                busy: _workingStep != null,
              ),
              if (structure != null) ...[
                const SizedBox(height: 16),
                DetailList(rows: [
                  DetailRow('Brand', structure.brand, mono: true),
                  DetailRow('Atoms', '${structure.atoms}', mono: true),
                  DetailRow('Tracks',
                      '${structure.hasVideo ? 'video' : '—'} / ${structure.hasAudio ? 'audio' : '—'}',
                      mono: true),
                  DetailRow(
                      'Size',
                      '${(structure.bytes / (1024 * 1024)).toStringAsFixed(2)} MB',
                      mono: true),
                ]),
              ],
              if (_embedOutcome != null) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: _downloadMarked,
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('Download'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _shareMarked,
                      icon: const Icon(Icons.ios_share, size: 18),
                      label: const Text('Share'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                PublishClaimButton(
                  medium: TraceMedium.video,
                  owner: _embedOutcome!.payload.owner,
                  subject: _embedOutcome!.payload.document,
                  reference: _embedOutcome!.payload.identifier ??
                      _embedOutcome!.payload.signature ??
                      '',
                  issued: _embedOutcome!.payload.issued,
                  alg: _embedOutcome!.payload.alg,
                  kid: _embedOutcome!.payload.kid,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        EmCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MonoLabel('Verification report'),
              const SizedBox(height: 14),
              ..._buildReport(),
              const SizedBox(height: 14),
              const Text(
                'Prototype note: the identifier is carried in a uuid atom and signed with your account key for illustration. Production will distribute ownership across sample tables and metadata boxes so it survives remuxing.',
                style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: EmColors.mutedForeground),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildReport() {
    if (_workingStep != null) {
      return [
        Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: EmColors.accent),
            ),
            const SizedBox(width: 12),
            Text('$_workingStep…',
                style: const TextStyle(
                    fontSize: 13, color: EmColors.foreground)),
          ],
        ),
      ];
    }
    if (_error != null) {
      return [
        StatusBanner(
            ok: false, title: 'Something went wrong', subtitle: _error!),
      ];
    }

    final recovered = _mode == VideoMode.embed
        ? _embedOutcome?.recovered
        : _verifyOutcome?.recovered;
    final claimStatus = _mode == VideoMode.embed
        ? _embedOutcome?.claimStatus
        : _verifyOutcome?.claimStatus;
    final structureMatch = _mode == VideoMode.embed
        ? _embedOutcome?.structureMatch
        : _verifyOutcome?.structureMatch;
    final recheckId = _mode == VideoMode.embed
        ? _embedOutcome?.recheckId
        : _verifyOutcome?.recheckId;
    final raw =
        _mode == VideoMode.embed ? _embedOutcome?.raw : _verifyOutcome?.raw;
    final hasResult = _mode == VideoMode.embed
        ? _embedOutcome != null
        : _verifyOutcome != null;

    if (!hasResult) {
      return [
        const Text(
          'Waiting for a video. The structural identifier and verification result appear here once a file has been fingerprinted or scanned.',
          style: TextStyle(fontSize: 13, color: EmColors.mutedForeground),
        ),
      ];
    }

    final banner = claimBanner(claimStatus ?? ClaimStatus.missing);
    final payload = _mode == VideoMode.embed
        ? _embedOutcome?.payload
        : _verifyOutcome?.recovered;

    return [
      StatusBanner(
        ok: banner.ok,
        title: banner.title,
        subtitle: banner.subtitle,
      ),
      const SizedBox(height: 14),
      DetailList(rows: [
        DetailRow('Owner', recovered?.owner ?? '—'),
        DetailRow('Document', recovered?.document ?? '—', mono: true),
        DetailRow('Structural ID', recovered?.identifier ?? '—', mono: true),
        DetailRow('Recomputed ID', recheckId ?? '—', mono: true),
        DetailRow(
            'Structure match',
            (structureMatch ?? false) ? 'identical' : 'mismatch',
            mono: true),
        DetailRow(
            'Key id',
            _kidLabel(payload?.alg ?? recovered?.alg, payload?.kid ?? recovered?.kid),
            mono: true),
        DetailRow('Round trip', '$_elapsedMs ms', mono: true),
      ]),
      if (_mode == VideoMode.embed) ...[
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _exportReport,
          icon: const Icon(Icons.download_outlined, size: 18),
          label: const Text('Export verification report'),
        ),
        if (_reportStatus != null) ...[
          const SizedBox(height: 8),
          Text(_reportStatus!.toUpperCase(),
              style: emMonoLabel(color: EmColors.mutedForeground, size: 9)),
        ],
      ],
      const SizedBox(height: 14),
      PayloadViewer(title: 'Extracted identifier payload', raw: raw),
    ];
  }

  static String _kidLabel(String? alg, String? kid) {
    if (alg == null || alg.isEmpty || alg == claimAlgFnv16) return 'legacy';
    if (kid != null && kid.isNotEmpty) return kid;
    return 'legacy';
  }
}
