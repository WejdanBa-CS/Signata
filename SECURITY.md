# Security

We take security seriously for Signata, especially around claim keys, on-device auth, and trace tooling.

## Reporting a vulnerability

**Please do not** open public GitHub issues for security bugs.

Email **FocusMindDev@gmail.com** with:

- Description of the issue
- Steps to reproduce
- Impact (what an attacker could access or do)
- Your GitHub username (optional, for credit)

We aim to respond within a few business days.

## Scope

In scope:

- Authentication bypass, weak local crypto, or recovery-kit tampering
- Watermark / fingerprint forgery or verification bypass
- Unsafe URL handling in Trace (open redirects, unexpected fetches)
- Data leaks from optional registry integration
- Android signing or OAuth misconfiguration documented in this repo

Out of scope:

- Social engineering, physical device access
- Denial of service without a practical exploit path
- Issues in third-party services (Google Sign-In, Play Console)
- Attacks that require the victim to import a malicious recovery kit they did not create

## Safe harbor

Good-faith research that avoids privacy violations and service disruption is appreciated.

## Secrets checklist

**Never commit:**

- `google_oauth.env` (use `google_oauth.example.env` only)
- `android/key.properties`, `*.jks`, `*.keystore`
- Real Google OAuth client IDs in source (build with `--dart-define-from-file` or paste at runtime in Account)

Android SHA-1 fingerprints in docs are **not secrets** (they appear in signed APKs) but keep upload keystore passwords local only.

CI runs a basic secret pattern scan on every push.

## OWASP-aligned controls (Cheat Sheet Series)

| Control | Status | Notes |
|--------|--------|-------|
| **Authentication** | Strong | PBKDF2-SHA256, TOTP 2FA, lockout, secure session storage |
| **Cryptography** | Strong | Claim keys and watermarks stay on-device; recovery kit integrity checks |
| **Input validation** | Hardened | Trace URLs validated in `lib/core/safe_url.dart` — http(s) only, no private/metadata hosts, no embedded credentials |
| **SSRF (Trace / registry)** | Hardened | Block localhost, RFC1918, link-local, and CGNAT ranges before any outbound fetch; registry base must be **https** |
| **Rate limiting** | Hardened | Trace scans capped at 40/hour per device session (`TraceRateLimiter`) |
| **Logging / errors** | Good | Neutral auth errors; remote registry failures logged without leaking secrets |
| **Secrets** | Good | OAuth and keystore material via env / dart-define only; CI secret scan |
| **Transport** | Good | Registry requires HTTPS; Trace allows public http(s) media URLs only after host validation |

### Trace URL policy

- Allowed: public `http://` and `https://` media or social page URLs
- Blocked: `file://`, `ftp://`, `localhost`, `.local`, `127.0.0.0/8`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `169.254.0.0/16`, `100.64.0.0/10`, URLs with userinfo

### Optional registry

Set `SIGNATA_REGISTRY_URL` to a **public https** endpoint. Invalid or private URLs are ignored at configure time. Claim references in remote lookups are length-capped and URL-encoded.
