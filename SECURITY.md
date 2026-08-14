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
