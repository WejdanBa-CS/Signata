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
6. Optional for debug without rebuild: Account → Paste Web client ID.

## Build the App Bundle

```powershell
.\tool\build_release.ps1
```

Output: `build/app/outputs/bundle/release/app-release.aab`

Upload that AAB in Play Console → Closed testing (then Production).

## Debug run with Google

```powershell
.\tool\run_debug.ps1
```

Uses `google_oauth.env` when present; otherwise email-only Google button stays hidden.

## Signing

- Upload keystore: `android/upload-keystore.jks` (local only, gitignored)
- Passwords: `android/key.properties` (local only, gitignored)
- Keep a secure backup of both — losing them blocks future updates unless you use Play App Signing recovery.

## Store listing screenshots

Phone captures for Play Console / README live in [`docs/screenshots/`](./screenshots/):

- `01-home.png` — hero / brand
- `02-capabilities-image.png` — image watermarking
- `03-capabilities-audio-video.png` — audio + video
- `04-tools.png` — protect & verify hub
- `05-trace.png` — Trace / Instagram scan

Upload these (or cropped phone-frame variants) under Play Console → Main store listing → Phone screenshots.

## Smoke test before upload

- [ ] Email signup → activate → Home
- [ ] Export / import recovery kit (Account)
- [ ] Image protect → verify → report export
- [ ] Trace: Check local file finds your mark
- [ ] Share image from Files into Signata → Trace check
- [ ] Social URL scan shows fallback warning
- [ ] Google Sign-In (debug + release SHA configured)
- [ ] Share intent while logged out still opens Trace after login
- [ ] Delete account wipes local data
- [ ] R8 release install: Google + share ingress still work

## Notes

- Trace prefers **shared/local files** over post URLs (platforms strip marks).
- Freemium Premium/ads are demo billing until Play Billing / AdMob are wired.
- `android:allowBackup="false"`; mailto queries are in the manifest.
