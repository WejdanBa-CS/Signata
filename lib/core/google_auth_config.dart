/// Google OAuth client IDs for Sign-In.
///
/// Create these in Google Cloud Console (APIs & Services → Credentials):
/// 1. OAuth client type **Web application** → use its ID as [serverClientId]
/// 2. OAuth client type **Android** with package `app.signata.signata` + SHA-1
///    (needed for Google to trust this app; you usually do NOT paste that ID here)
///
/// Fill the values below, or pass them at run time:
/// `flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=....apps.googleusercontent.com`
library;

class GoogleAuthConfig {
  /// Web client ID — required on Android as `serverClientId`.
  static const String serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );

  /// Optional. Mostly used on iOS/Web. On Android, leave empty unless you have
  /// a reason to override the default client.
  static const String clientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue: '',
  );

  static bool get hasServerClientId => serverClientId.trim().isNotEmpty;
}
