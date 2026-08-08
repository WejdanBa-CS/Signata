# EchoMark (Flutter)

Invisible ownership. Verifiable authenticity.

Native Flutter conversion of the EchoMark web prototype — digital watermarking for images and structural fingerprinting for PDFs, processing entirely on-device.

## What's included

- **Home** — full landing story (features, how it works, architecture, roadmap)
- **Image tool** — LSB watermark embed + standalone verify
- **PDF tool** — structural SHA-256 fingerprint embed + standalone verify
- **History** — local on-device record of every embed/verify run
- Sealed JSON verification reports (shareable)
- Watermarked files that verify against the original website prototype (same bit layout / marker format)

## Run

```sh
flutter pub get
flutter run
```

## Test

```sh
flutter test
flutter analyze
```

## Build Android APK

```sh
flutter build apk --release
```

The APK lands at `build/app/outputs/flutter-apk/app-release.apk`.

> On Windows, Flutter plugin builds need **Developer Mode** enabled (`start ms-settings:developers`) so symlinks work. If a Gradle build fails with a lock error, stop other Gradle/Android Studio processes and retry.

## Project layout

```
lib/
  core/           # codecs + sealed report + history
  screens/        # Home / Image / PDF / History
  widgets/        # shared EchoMark UI
  theme.dart
  main.dart
assets/
website-source/   # original React site (reference)
```
