import 'claim_crypto.dart';

/// Shared verify banner copy for tool screens.
({bool ok, String title, String subtitle}) claimBanner(ClaimStatus status) {
  switch (status) {
    case ClaimStatus.authenticated:
      return (
        ok: true,
        title: 'Authenticated with your Signata key',
        subtitle: ClaimCrypto.describe(status),
      );
    case ClaimStatus.selfConsistent:
      return (
        ok: true,
        title: 'Legacy fingerprint (unsigned)',
        subtitle:
            'Structure checks out, but it is not bound to your account key.',
      );
    case ClaimStatus.foreignKey:
      return (
        ok: false,
        title: 'Signed by another Signata key',
        subtitle: ClaimCrypto.describe(status),
      );
    case ClaimStatus.present:
      return (
        ok: false,
        title: 'Fingerprint found but invalid',
        subtitle: ClaimCrypto.describe(status),
      );
    case ClaimStatus.missing:
      return (
        ok: false,
        title: 'No fingerprint found',
        subtitle: ClaimCrypto.describe(status),
      );
  }
}

/// Trace-specific banner — explains platform stripping when nothing is found.
({bool ok, String title, String subtitle}) traceResultBanner({
  required ClaimStatus status,
  String? error,
  String? note,
  bool socialHost = false,
}) {
  if (error != null && error.isNotEmpty) {
    return (ok: false, title: 'Could not scan URL', subtitle: error);
  }
  if (status == ClaimStatus.missing) {
    return (
      ok: false,
      title: socialHost
          ? 'No fingerprint on this post'
          : 'No fingerprint found',
      subtitle: note ??
          (socialHost
              ? 'Social apps often recompress media and can strip hidden marks. '
                  'Try the original protected file or a direct media CDN link.'
              : ClaimCrypto.describe(status)),
    );
  }
  return claimBanner(status);
}

bool claimCountsAsVerified(ClaimStatus status) =>
    status == ClaimStatus.authenticated;
