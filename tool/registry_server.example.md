# Optional Signata claim registry

The app can sync published claims to a remote HTTP registry when launched with:

```sh
flutter run --dart-define=SIGNATA_REGISTRY_URL=https://your-host.example
```

## Expected API

### `POST /claims`
JSON body matches a published claim (`id`, `medium`, `owner`, `subject`, `reference`, `issued`, `publisherId`, `publishedAt`, optional `alg` / `kid` / `note`).

Respond `2xx` on success.

### `GET /claims/:reference`
Return the claim JSON (or `{ "claim": { ... } }`) for fingerprint lookup.

Without `SIGNATA_REGISTRY_URL`, claims stay on-device and URL tracing still works by reading fingerprints embedded in the downloaded media.
