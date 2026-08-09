import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/claim_crypto.dart';
import '../core/claim_status_ui.dart';
import '../core/history.dart';
import '../core/image_watermark.dart';
import '../core/report.dart';
import '../core/share_utils.dart';
import '../theme.dart';
import '../widgets/em_widgets.dart';

enum ToolMode { embed, verify }

class ImageToolScreen extends StatefulWidget {
  const ImageToolScreen({super.key, this.defaultOwner = 'Studio Nova'});

  final String defaultOwner;

  @override
  State<ImageToolScreen> createState() => _ImageToolScreenState();
}

class _ImageToolScreenState extends State<ImageToolScreen> {
  late final _ownerController =
      TextEditingController(text: widget.defaultOwner);

  ToolMode _mode = ToolMode.embed;
  String? _workingStep;
  String? _error;
  String? _fileName;
  int _elapsedMs = 0;

  EmbedOutcome? _embedOutcome;
  ExtractOutcome? _verifyOutcome;
  WatermarkPayload? _verifyPayload;

  String? _reportStatus;

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
    final picked = await FilePicker.pickFiles(type: FileType.image);
    final file = picked?.files.firstOrNull;
    if (file == null) return;
    final bytes = await file.readAsBytes();

    _reset();
    setState(() => _fileName = file.name);
    final stopwatch = Stopwatch()..start();

    try {
      final claimKey = await AccountClaimKeys.current();
      if (_mode == ToolMode.embed) {
        setState(() => _workingStep = 'Embedding signed ownership fingerprint');
        final outcome = await embedWatermark(
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
          medium: 'image',
          action: 'embed',
          subject: file.name,
          owner: outcome.payload.owner,
          verified: claimCountsAsVerified(outcome.claimStatus),
          reference: outcome.payload.signature,
          at: DateTime.now(),
        ));
      } else {
        setState(() => _workingStep = 'Scanning for a watermark');
        final outcome = await extractWatermark(bytes, claimKey: claimKey);
        stopwatch.stop();
        final payload = WatermarkPayload.tryParse(outcome.raw);
        if (!mounted) return;
        setState(() {
          _verifyOutcome = outcome;
          _verifyPayload = payload;
          _workingStep = null;
          _elapsedMs = stopwatch.elapsedMilliseconds;
        });
        await HistoryStore.add(HistoryEntry(
          medium: 'image',
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
      bytes: outcome.markedPng,
      fileName: 'signata-${_fileName ?? 'image'}.png',
      mimeType: 'image/png',
      text: 'Watermarked with Signata',
    );
  }

  Future<void> _exportReport() async {
    final outcome = _embedOutcome;
    if (outcome == null) return;
    setState(() => _reportStatus = 'Sealing…');
    try {
      final recovered = outcome.recovered;
      final sealed = sealReport(ReportBody(
        medium: 'image',
        subject: _fileName ?? outcome.payload.asset,
        owner: outcome.payload.owner,
        verified: claimCountsAsVerified(outcome.claimStatus),
        issued: outcome.payload.issued,
        generated: DateTime.now().toUtc().toIso8601String(),
        evidence: {
          'method': 'LSB pixel-domain watermark',
          'embeddedSignature': outcome.payload.signature,
          'recoveredSignature': recovered?.signature,
          'signatureMatch':
              outcome.payload.signature == recovered?.signature,
          'asset': outcome.payload.asset,
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
          tag: 'Live prototype',
          title: 'Embed, extract, verify — on your device',
          desc:
              'Pick an image and Signata encodes an ownership fingerprint into the pixel data, then reads it back out of the delivered file and verifies the signature. Nothing leaves your device.',
        ),
        const SizedBox(height: 20),
        SegmentedButton<ToolMode>(
          segments: const [
            ButtonSegment(
              value: ToolMode.embed,
              label: Text('Protect'),
              icon: Icon(Icons.fingerprint, size: 18),
            ),
            ButtonSegment(
              value: ToolMode.verify,
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
              if (_mode == ToolMode.embed) ...[
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
                icon: _mode == ToolMode.embed
                    ? Icons.upload_outlined
                    : Icons.image_search_outlined,
                title: _mode == ToolMode.embed
                    ? 'Choose an image to protect'
                    : 'Choose an image to check',
                hint: _mode == ToolMode.embed
                    ? 'PNG, JPG or WEBP — processed locally'
                    : 'Works with any PNG carrying an Signata watermark',
                buttonLabel: 'Choose an image',
                onPick: _pickAndRun,
                fileName: _fileName,
                busy: _workingStep != null,
              ),
              if (_embedOutcome != null) ...[
                const SizedBox(height: 16),
                _ImagePair(outcome: _embedOutcome!),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _shareMarked,
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text('Share watermarked PNG'),
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
              Text(
                _mode == ToolMode.embed
                    ? 'Prototype note: this demo uses scattered least-significant-bit encoding signed with your account key for illustration. The production engine adds transform-robust embedding server-side.'
                    : 'Verification recomputes the signed ownership claim from the recovered payload, so a forged or edited fingerprint is detected. Lossy formats (JPG) destroy LSB watermarks by design.',
                style: const TextStyle(
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
        StatusBanner(ok: false, title: 'Something went wrong', subtitle: _error!),
      ];
    }

    final embed = _embedOutcome;
    if (_mode == ToolMode.embed && embed != null) {
      final recovered = embed.recovered;
      final banner = claimBanner(embed.claimStatus);
      var subtitle = banner.subtitle;
      if (embed.resized) {
        subtitle = '$subtitle Image was resized to fit the LSB carrier.';
      }
      return [
        StatusBanner(
          ok: banner.ok,
          title: banner.title,
          subtitle: subtitle,
        ),
        const SizedBox(height: 14),
        DetailList(rows: [
          DetailRow('Owner', recovered?.owner ?? '—'),
          DetailRow('Asset', recovered?.asset ?? '—', mono: true),
          DetailRow('Issued', _formatDate(recovered?.issued)),
          DetailRow('Signature', recovered?.signature ?? '—', mono: true),
          DetailRow(
              'Key id',
              _kidLabel(recovered?.alg ?? embed.payload.alg,
                  recovered?.kid ?? embed.payload.kid),
              mono: true),
          DetailRow(
              'Payload density',
              '${embed.bitsUsed} / ${embed.capacityBits} bits',
              mono: true),
          DetailRow('Round trip', '$_elapsedMs ms', mono: true),
        ]),
        const SizedBox(height: 14),
        _exportRow(),
        const SizedBox(height: 14),
        PayloadViewer(title: 'Extracted payload', raw: embed.recoveredRaw),
      ];
    }

    final verifyPayload = _verifyPayload;
    if (_mode == ToolMode.verify && _verifyOutcome != null) {
      final banner = claimBanner(_verifyOutcome!.claimStatus);
      return [
        StatusBanner(
          ok: banner.ok,
          title: banner.title,
          subtitle: banner.subtitle,
        ),
        if (verifyPayload != null) ...[
          const SizedBox(height: 14),
          DetailList(rows: [
            DetailRow('Owner', verifyPayload.owner),
            DetailRow('Asset', verifyPayload.asset, mono: true),
            DetailRow('Issued', _formatDate(verifyPayload.issued)),
            DetailRow('Signature', verifyPayload.signature, mono: true),
            DetailRow(
                'Key id',
                _kidLabel(verifyPayload.alg, verifyPayload.kid),
                mono: true),
            DetailRow('Scan time', '$_elapsedMs ms', mono: true),
          ]),
          const SizedBox(height: 14),
          PayloadViewer(
              title: 'Extracted payload', raw: _verifyOutcome!.raw),
        ],
      ];
    }

    return [
      const Text(
        'Waiting for an image. Results appear here once a fingerprint has been embedded or scanned.',
        style: TextStyle(fontSize: 13, color: EmColors.mutedForeground),
      ),
    ];
  }

  Widget _exportRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
    );
  }

  static String _formatDate(String? iso) {
    if (iso == null) return '—';
    final parsed = DateTime.tryParse(iso)?.toLocal();
    if (parsed == null) return iso;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${parsed.year}-${two(parsed.month)}-${two(parsed.day)} '
        '${two(parsed.hour)}:${two(parsed.minute)}';
  }

  static String _kidLabel(String? alg, String? kid) {
    if (alg == null || alg.isEmpty || alg == claimAlgFnv16) return 'legacy';
    if (kid != null && kid.isNotEmpty) return kid;
    return 'legacy';
  }
}

class _ImagePair extends StatelessWidget {
  const _ImagePair({required this.outcome});

  final EmbedOutcome outcome;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _thumb(outcome.originalPng, 'Original', EmColors.border,
              EmColors.mutedForeground),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _thumb(
              outcome.markedPng,
              'Watermarked',
              EmColors.primary.withValues(alpha: 0.4),
              EmColors.primary),
        ),
      ],
    );
  }

  Widget _thumb(
      Uint8List bytes, String caption, Color border, Color captionColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 1,
              child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(caption.toUpperCase(),
            style: emMonoLabel(color: captionColor, size: 9)),
      ],
    );
  }
}
