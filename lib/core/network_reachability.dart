/// Lightweight connectivity probe (no extra package).
library;

import 'dart:io';

Future<bool> hasNetworkReachability() async {
  try {
    final result = await InternetAddress.lookup('dns.google')
        .timeout(const Duration(seconds: 3));
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}
