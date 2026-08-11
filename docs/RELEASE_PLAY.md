# Play release checklist (Signata)

## Google Sign-In (required for “Continue with Google”)

1. Open [Google Cloud Credentials](https://console.cloud.google.com/apis/credentials).
2. Create **OAuth client → Web application**. Copy the Client ID.
3. Create **OAuth client → Android**:
   - Package name: `app.signata.signata`
   - Add these SHA-1 fingerprints (same client or one client each):
     - Debug: `0A:3A:67:69:E8:44:A7:A5:0A:1B:FD:CD:61:A1:32:5C:2B:F6:9F:AA`
     - Upload/release: `73:17:8E:4C:0D:25:57:C6:67:17:6C:C8:7F:91:C7:7B:89:0C:77:FA`
4. Copy `google_oauth.example.env` → `google_oauth.env` and set:
   ```
   GOOGLE_SERVER_CLIENT_ID=YOUR_REAL_WEB_CLIENT_ID.apps.googleusercontent.com
   ```
5. After the first Play upload, open **Play Console → App integrity** and add the
   **App signing key certificate SHA-1** to the Android OAuth client as well.

## Build the App Bundle

```powershell
.\tool\build_release.ps1
```

Output: `build/app/outputs/bundle/release/app-release.aab`

Upload that AAB in Play Console → Production / Testing.

## Signing

- Upload keystore: `android/upload-keystore.jks` (local only, gitignored)
- Passwords: `android/key.properties` (local only, gitignored)
- Keep a secure backup of both — losing them blocks future updates unless you use Play App Signing recovery.
