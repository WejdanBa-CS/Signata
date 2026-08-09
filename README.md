# Signata (Flutter)

Invisible ownership. Verifiable authenticity.

Native Flutter app for digital watermarking — images, audio, video, and PDFs — processing entirely on-device.

## What's included

- **Home** — full landing story (features, how it works, architecture, roadmap)
- **Tools hub** — Image, Audio, Video, and PDF protect/verify flows
- **Auth** — email accounts + Google Sign-In gate
- **History** — local on-device record of every embed/verify run
- Sealed JSON verification reports (shareable)

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
  core/           # codecs + sealed report + history + auth
  screens/        # Home / Tools / History / Account
  widgets/        # shared Signata UI
  theme.dart
  main.dart
assets/
website-source/   # original React site (reference)
```
