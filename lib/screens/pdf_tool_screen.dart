import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/claim_crypto.dart';
import '../core/claim_status_ui.dart';
import '../core/history.dart';
import '../core/onboarding.dart';
import '../core/pdf_fingerprint.dart';
import '../core/report.dart';
import '../core/share_utils.dart';
import '../core/trace_models.dart';
import '../core/usage_entitlements.dart';
import '../theme.dart';
import '../widgets/em_widgets.dart';
import '../widgets/publish_claim_button.dart';
import '../widgets/usage_paywall.dart';

enum PdfMode { embed, verify }

class PdfToolScreen extends StatefulWidget {
  const PdfToolScreen({super.key, this.defaultOwner = ''});

  final String defaultOwner;

  @override
  State<PdfToolScreen> createState() => _PdfToolScreenState();
}

class _PdfToolScreenState extends State<PdfToolScreen> {
  late final _ownerController =
      TextEditingController(text: widget.defaultOwner);

  PdfMode _mode = PdfMode.embed;
  String? _workingStep;
  String? _error;
  String? _fileName;
  int _elapsedMs = 0;

  PdfEmbedOutcome? _embedOutcome;
  PdfVerifyOutcome? _verifyOutcome;

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
      _reportStatus = null;
      _elapsedMs = 0;
    });
  }

  Future<void> _pickAndRun() async {
    if (_mode == PdfMode.embed) {
      final allowed = await ensureUsage(context, UsageKind.protect);
      if (!allowed || !mounted) return;
    }
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    final file = picked?.files.firstOrNull;
    if (file == null) return;
    final bytes = await file.readAsBytes();

    _reset();
    setState(() => _fileName = file.name);
    final stopwatch = Stopwatch()..start();

    try {
      final claimKey = await AccountClaimKeys.current();
      if (_mode == PdfMode.embed) {
        setState(() => _workingStep = 'Deriving structural identifier');
        final outcome = await embedPdfFingerprint(
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
          medium: 'pdf',
          action: 'embed',
          subject: file.name,
          owner: outcome.payload.owner,
          verified: claimCountsAsVerified(outcome.claimStatus),
          reference: outcome.payload.structuralIdentifier(),
          at: DateTime.now(),
        ));
        await commitUsage(UsageKind.protect);
        await OnboardingFlags.instance.markProtectedOnce();
      } else {
        setState(() => _workingStep = 'Extracting & verifying');
        final outcome = await verifyPdfFingerprint(bytes, claimKey: claimKey);
        stopwatch.stop();
        if (!mounted) return;
        setState(() {
          _verifyOutcome = outcome;
          _workingStep = null;
          _elapsedMs = stopwatch.elapsedMilliseconds;
        });
        await HistoryStore.add(HistoryEntry(
          medium: 'pdf',
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
      fileName: 'signata-${_fileName ?? 'document.pdf'}',
      mimeType: 'application/pdf',
      text: 'Fingerprinted with Signata',
    );
  }

  Future<void> _downloadMarked() async {
    final outcome = _embedOutcome;
    if (outcome == null) return;
    try {
      final path = await downloadBytes(
        bytes: outcome.markedBytes,
        fileName: 'signata-${_fileName ?? 'document.pdf'}',
        dialogTitle: 'Download fingerprinted PDF',
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
      final claimKey = await AccountClaimKeys.current();
      final sealed = sealReport(ReportBody(
        medium: 'pdf',
        subject: outcome.recovered?.document ?? _fileName ?? 'document.pdf',
        owner: outcome.recovered?.owner ?? 'Unknown',
        verified: claimCountsAsVerified(outcome.claimStatus),
        issued: outcome.payload.issued,
        generated: DateTime.now().toUtc().toIso8601String(),
        evidence: {
          'method': 'Structural SHA-256 fingerprint',
          'structuralId': outcome.recovered?.identifier,
          'recomputedId': outcome.recheckId,
          'structureMatch': outcome.structureMatch,
          'structure': outcome.recovered?.structure.toJson(),
          'roundTripMs': _elapsedMs,
        },
      ), claimKey: claimKey);
      if (!verifySealedReport(sealed, claimKey: claimKey)) {
        throw Exception('Seal self-check failed.');
      }
      await shareBytes(
        bytes: Uint8List.fromList(sealed.toPrettyJson().codeUnits),
        fileName: reportFileName(_fileName ?? 'document.pdf'),
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
    final structure = _mode == PdfMode.embed
        ? _embedOutcome?.recovered?.structure
        : _verifyOutcome?.recovered?.structure;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      children: [
        const SectionHeading(
          tag: 'PDF fingerprinting',
          title: 'Fingerprint a document, recover its identifier',
          desc:
              'Signata profiles the internal structure of a PDF — version, object graph, streams and cross-reference tables — derives a SHA-256 structural identifier, then hides it inside the delivered file and reads it back to verify ownership.',
        ),
        const SizedBox(height: 20),
        SegmentedButton<PdfMode>(
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: EmColors.accent,
            selectedForegroundColor: EmColors.accentForeground,
          ),
          segments: const [
            ButtonSegment(
              value: PdfMode.embed,
              label: Text('Protect'),
              icon: Icon(Icons.fingerprint, size: 18),
            ),
            ButtonSegment(
              value: PdfMode.verify,
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
              if (_mode == PdfMode.embed) ...[
                const UsageStatusBanner(kind: UsageKind.protect),
                const MonoLabel('Ownership claim'),
                const SizedBox(height: 10),
                TextField(
                  controller: _ownerController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    hintText: 'Creator or studio name',
                    helperText:
                        'Bound to your Signata account — cannot be spoofed for authentication.',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              UploadBox(
                icon: Icons.picture_as_pdf_outlined,
                title: _mode == PdfMode.embed
                    ? 'Choose a PDF to fingerprint'
                    : 'Choose a PDF to check',
                hint: _mode == PdfMode.embed
                    ? 'PDF only — print/scan or flatten may remove the fingerprint'
                    : 'Check the original PDF you protected',
                buttonLabel: 'Choose a PDF',
                onPick: _pickAndRun,
                fileName: _fileName,
                tone: EmColors.accent,
                busy: _workingStep != null,
              ),
              if (structure != null) ...[
                const SizedBox(height: 16),
                DetailList(rows: [
                  DetailRow('PDF version', structure.version, mono: true),
                  DetailRow('Pages', '${structure.pages}', mono: true),
                  DetailRow('Objects', '${structure.objects}', mono: true),
                  DetailRow('Streams', '${structure.streams}', mono: true),
                  DetailRow('Xref tables', '${structure.xrefs}', mono: true),
                  DetailRow(
                      'Size',
                      '${(structure.bytes / 1024).toStringAsFixed(1)} KB',
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
                  medium: TraceMedium.pdf,
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
                'Prototype note: the identifier is carried in a trailing marker comment and signed with your account key for illustration. Production distributes it across object metadata and structural entropy so it survives re-saving and editing.',
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
        StatusBanner(ok: false, title: 'Something went wrong', subtitle: _error!),
      ];
    }

    final recovered = _mode == PdfMode.embed
        ? _embedOutcome?.recovered
        : _verifyOutcome?.recovered;
    final claimStatus = _mode == PdfMode.embed
        ? _embedOutcome?.claimStatus
        : _verifyOutcome?.claimStatus;
    final structureMatch = _mode == PdfMode.embed
        ? _embedOutcome?.structureMatch
        : _verifyOutcome?.structureMatch;
    final recheckId = _mode == PdfMode.embed
        ? _embedOutcome?.recheckId
        : _verifyOutcome?.recheckId;
    final raw =
        _mode == PdfMode.embed ? _embedOutcome?.raw : _verifyOutcome?.raw;
    final hasResult =
        _mode == PdfMode.embed ? _embedOutcome != null : _verifyOutcome != null;

    if (!hasResult) {
      return [
        const Text(
          'Waiting for a document. The structural identifier and verification result appear here once a PDF has been fingerprinted or scanned.',
          style: TextStyle(fontSize: 13, color: EmColors.mutedForeground),
        ),
      ];
    }

    final banner = claimBanner(claimStatus ?? ClaimStatus.missing);
    final payload = _mode == PdfMode.embed
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
        DetailRow('Issued', _formatDate(recovered?.issued), mono: true),
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
      if (_mode == PdfMode.embed) ...[
        const SizedBox(height: 14),
        Column(
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
                  style:
                      emMonoLabel(color: EmColors.mutedForeground, size: 9)),
            ],
          ],
        ),
      ],
      const SizedBox(height: 14),
      PayloadViewer(title: 'Extracted identifier payload', raw: raw),
    ];
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
