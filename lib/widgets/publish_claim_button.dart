import 'package:flutter/material.dart';

import '../core/claim_publisher.dart';
import '../core/trace_models.dart';
import '../theme.dart';

/// One-tap publish after a successful protect, for internet tracing.
class PublishClaimButton extends StatefulWidget {
  const PublishClaimButton({
    super.key,
    required this.medium,
    required this.owner,
    required this.subject,
    required this.reference,
    required this.issued,
    this.alg,
    this.kid,
  });

  final TraceMedium medium;
  final String owner;
  final String subject;
  final String reference;
  final String issued;
  final String? alg;
  final String? kid;

  @override
  State<PublishClaimButton> createState() => _PublishClaimButtonState();
}

class _PublishClaimButtonState extends State<PublishClaimButton> {
  bool _busy = false;
  String? _status;

  Future<void> _publish() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final claim = await ClaimPublisher.publishProtected(
        medium: widget.medium,
        owner: widget.owner,
        subject: widget.subject,
        reference: widget.reference,
        issued: widget.issued,
        alg: widget.alg,
        kid: widget.kid,
      );
      if (!mounted) return;
      setState(() {
        _status = claim == null
            ? 'Could not publish claim.'
            : claim.remoteSynced
                ? 'Published & synced for web tracing'
                : 'Published on this device for web tracing';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() =>
          _status = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: _busy ? null : _publish,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.public, size: 18),
          label: Text(_busy ? 'Publishing…' : 'Publish for web tracing'),
        ),
        if (_status != null) ...[
          const SizedBox(height: 8),
          Text(
            _status!.toUpperCase(),
            style: emMonoLabel(color: EmColors.mutedForeground, size: 9),
          ),
        ],
      ],
    );
  }
}
