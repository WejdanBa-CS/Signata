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
        title: 'Claim is self-consistent',
        subtitle:
            'Legacy fingerprint checks out, but it is not bound to your account key.',
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

bool claimCountsAsVerified(ClaimStatus status) =>
    status == ClaimStatus.authenticated ||
    status == ClaimStatus.selfConsistent;
