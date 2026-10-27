# Stone & Banner

Original offline-first Android strategy game, now built in **Flutter/Dart** on Nox. Stage 1 is a compiling prototype, not a full match: Home / Board / Rules, seeded balanced 19-hex preview, functional turn counter, immutable pure-Dart rules engine and tests.

## Build on Nox

```sh
flutter pub get
flutter analyze
buildq --wait -- flutter test
buildq --wait -- flutter build apk --release
```

Release APK: `build/app/outputs/flutter-apk/app-release.apk` (local testing only). Package ID `nz.presley.stoneandbanner`. No network, account or analytics features in Stage 1. Use Nox Waydroid for Android testing; do not require Glass.

All future gameplay legality, scoring and deterministic event/replay logic belongs in `lib/engine/`, never widgets. See `docs/ROADMAP.md`, `docs/RULES.md`, `docs/GLOSSARY.md`, and `docs/IP.md`. Do not publish before original-art, legal and security review.

The legacy Stage 1 Kotlin prototype remains on the powered-off Glass machine; Nox is canonical for all new work. The behaviour of its engine and UI preview was ported from an inspection of the original files.
