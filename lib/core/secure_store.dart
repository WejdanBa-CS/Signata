/// Shared encrypted on-device storage for auth, claim keys, and secrets.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// flutter_secure_storage 11 uses Keystore-backed AES-GCM by default on Android.
const FlutterSecureStorage signataSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(),
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);
