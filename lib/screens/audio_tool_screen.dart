import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/audio_watermark.dart';
import '../core/claim_crypto.dart';
import '../core/claim_status_ui.dart';
import '../core/history.dart';
import '../core/report.dart';
import '../core/share_utils.dart';
import '../core/trace_models.dart';
import '../theme.dart';
import '../widgets/em_widgets.dart';
import '../widgets/publish_claim_button.dart';

enum AudioMode { embed, verify }

class AudioToolScreen extends StatefulWidget {
  const AudioToolScreen({super.key, this.defaultOwner = ''});

  final String defaultOwner;

  @override
  State<AudioToolScreen> createState() => _AudioToolScreenState();
}

class _AudioToolScreenState extends State<AudioToolScreen> {
  late final _ownerController =
      TextEditingController(text: widget.defaultOwner);

  AudioMode _mode = AudioMode.embed;
  String? _workingStep;
  String? _error;
  String? _fileName;
  int _elapsedMs = 0;
  String? _reportStatus;

  AudioEmbedOutcome? _embedOutcome;
  AudioExtractOutcome? _verifyOutcome;
  AudioPayload? _verifyPayload;

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
      _verifyPayload = null;
      _reportStatus = null;
      _elapsedMs = 0;
    });
  }

  Future<void> _pickAndRun() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['wav'],
    );
    final file = picked?.files.firstOrNull;
    if (file == null) return;
    final bytes = await file.readAsBytes();

    _reset();
    setState(() => _fileName = file.name);
    final stopwatch = Stopwatch()..start();

    try {
      final claimKey = await AccountClaimKeys.current();
      if (_mode == AudioMode.embed) {
        setState(() => _workingStep = 'Embedding inaudible fingerprint');
        final outcome = await embedAudioWatermark(
          fileBytes: bytes,
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
          medium: 'audio',
          action: 'embed',
          subject: file.name,
          owner: outcome.payload.owner,
          verified: claimCountsAsVerified(outcome.claimStatus),
          reference: outcome.payload.signature,
          at: DateTime.now(),
        ));
      } else {
        setState(() => _workingStep = 'Scanning audio samples');
        final outcome = await extractAudioWatermark(bytes, claimKey: claimKey);
        stopwatch.stop();
        final payload = AudioPayload.tryParse(outcome.raw);
        if (!mounted) return;
        setState(() {
          _verifyOutcome = outcome;
          _verifyPayload = payload;
          _workingStep = null;
          _elapsedMs = stopwatch.elapsedMilliseconds;
        });
        await HistoryStore.add(HistoryEntry(
          medium: 'audio',
          action: 'verify',
          subject: file.name,
          owner: payload?.owner ?? 'Unknown',
          verified: claimCountsAsVerified(outcome.claimStatus),
          reference: payload?.signature ?? '—',
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
      bytes: outcome.markedWav,
      fileName: 'signata-${_fileName ?? 'audio.wav'}',
      mimeType: 'audio/wav',
      text: 'Watermarked with Signata',
    );
  }

  Future<void> _downloadMarked() async {
    final outcome = _embedOutcome;
    if (outcome == null) return;
    try {
      final path = await downloadBytes(
        bytes: outcome.markedWav,
        fileName: 'signata-${_fileName ?? 'audio.wav'}',
        dialogTitle: 'Download watermarked audio',
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
        medium: 'audio',
        subject: _fileName ?? outcome.payload.asset,
        owner: outcome.payload.owner,
        verified: claimCountsAsVerified(outcome.claimStatus),
        issued: outcome.payload.issued,
        generated: DateTime.now().toUtc().toIso8601String(),
        evidence: {
          'method': 'LSB PCM-domain watermark (16-bit WAV)',
          'embeddedSignature': outcome.payload.signature,
          'recoveredSignature': outcome.recovered?.signature,
          'sampleRate': outcome.sampleRate,
          'channels': outcome.channels,
          'payloadDensity':
              '${outcome.bitsUsed} / ${outcome.capacityBits} bits',
          'roundTripMs': _elapsedMs,
        },
      ));
      if (!verifySealedReport(sealed)) {
        throw Exception('Seal self-check failed.');
      }
      await shareBytes(
        bytes: Uint8List.fromList(sealed.toPrettyJson().codeUnits),
        fileName: reportFileName(_fileName ?? outcome.payload.asset),
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      children: [
        const SectionHeading(
          tag: 'Audio watermarking',
          title: 'Inaudible ownership in WAV',
          desc:
              'Signata flips the least-significant bit of 16-bit PCM samples to carry a signed ownership claim — inaudible, recoverable, processed on-device.',
        ),
        const SizedBox(height: 20),
        SegmentedButton<AudioMode>(
          segments: const [
            ButtonSegment(
              value: AudioMode.embed,
              label: Text('Protect'),
              icon: Icon(Icons.fingerprint, size: 18),
            ),
            ButtonSegment(
              value: AudioMode.verify,
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
              if (_mode == AudioMode.embed) ...[
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
                icon: Icons.graphic_eq,
                title: _mode == AudioMode.embed
                    ? 'Choose a WAV to protect'
                    : 'Choose a WAV to check',
                hint: '16-bit PCM WAV — processed locally',
                buttonLabel: 'Choose audio',
                onPick: _pickAndRun,
                fileName: _fileName,
                busy: _workingStep != null,
              ),
              if (_embedOutcome != null) ...[
                const SizedBox(height: 14),
                DetailList(rows: [
                  DetailRow('Sample rate', '${_embedOutcome!.sampleRate} Hz',
                      mono: true),
                  DetailRow('Channels', '${_embedOutcome!.channels}', mono: true),
                  DetailRow(
                      'Payload density',
                      '${_embedOutcome!.bitsUsed} / ${_embedOutcome!.capacityBits} bits',
                      mono: true),
                ]),
                const SizedBox(height: 12),
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
                  medium: TraceMedium.audio,
                  owner: _embedOutcome!.payload.owner,
                  subject: _embedOutcome!.payload.asset,
                  reference: _embedOutcome!.payload.signature,
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
                'Prototype note: this demo uses PCM least-significant-bit encoding for illustration. The production engine will target transform-domain embedding that survives compression and streaming re-encodes.',
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
                  strokeWidth: 2, color: EmColors.primary),
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

    if (_mode == AudioMode.embed && _embedOutcome != null) {
      final outcome = _embedOutcome!;
      final recovered = outcome.recovered;
      final banner = claimBanner(outcome.claimStatus);
      return [
        StatusBanner(
          ok: banner.ok,
          title: banner.title,
          subtitle: banner.subtitle,
        ),
        const SizedBox(height: 14),
        DetailList(rows: [
          DetailRow('Owner', recovered?.owner ?? '—'),
          DetailRow('Asset', recovered?.asset ?? '—', mono: true),
          DetailRow('Signature', recovered?.signature ?? '—', mono: true),
          DetailRow(
              'Key id',
              _kidLabel(recovered?.alg ?? outcome.payload.alg,
                  recovered?.kid ?? outcome.payload.kid),
              mono: true),
          DetailRow('Round trip', '$_elapsedMs ms', mono: true),
        ]),
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
        const SizedBox(height: 14),
        PayloadViewer(title: 'Extracted payload', raw: outcome.recoveredRaw),
      ];
    }

    if (_mode == AudioMode.verify && _verifyOutcome != null) {
      final payload = _verifyPayload;
      final banner = claimBanner(_verifyOutcome!.claimStatus);
      return [
        StatusBanner(
          ok: banner.ok,
          title: banner.title,
          subtitle: banner.subtitle,
        ),
        if (payload != null) ...[
          const SizedBox(height: 14),
          DetailList(rows: [
            DetailRow('Owner', payload.owner),
            DetailRow('Asset', payload.asset, mono: true),
            DetailRow('Signature', payload.signature, mono: true),
            DetailRow(
                'Key id', _kidLabel(payload.alg, payload.kid), mono: true),
            DetailRow(
                'Format',
                '${_verifyOutcome!.sampleRate} Hz · ${_verifyOutcome!.channels} ch',
                mono: true),
            DetailRow('Scan time', '$_elapsedMs ms', mono: true),
          ]),
          const SizedBox(height: 14),
          PayloadViewer(title: 'Extracted payload', raw: _verifyOutcome!.raw),
        ],
      ];
    }

    return [
      const Text(
        'Waiting for a WAV file. Results appear here once a fingerprint has been embedded or scanned.',
        style: TextStyle(fontSize: 13, color: EmColors.mutedForeground),
      ),
    ];
  }

  static String _kidLabel(String? alg, String? kid) {
    if (alg == null || alg.isEmpty || alg == claimAlgFnv16) return 'legacy';
    if (kid != null && kid.isNotEmpty) return kid;
    return 'legacy';
  }
}
