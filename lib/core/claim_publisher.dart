/// Convenience helpers to register a protected file for internet tracing.
library;

import 'auth.dart';
import 'claim_registry.dart';
import 'trace_models.dart';

class ClaimPublisher {
  ClaimPublisher._();

  static Future<PublishedClaim?> publishProtected({
    required TraceMedium medium,
    required String owner,
    required String subject,
    required String reference,
    required String issued,
    String? alg,
    String? kid,
    String? note,
  }) async {
    if (reference.trim().isEmpty || reference == '—') return null;
    if (!AuthService.instance.isSignedIn) return null;
    return ClaimRegistry.instance.publish(
      medium: medium,
      owner: owner,
      subject: subject,
      reference: reference,
      issued: issued,
      alg: alg,
      kid: kid,
      note: note,
    );
  }
}
