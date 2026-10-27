# Stone & Banner

Original offline-first Android strategy game, now built in **Flutter/Dart** on Nox. Stage 2 is a playable 3–4-seat pass-and-play match: 19 hexes, legal roads and settlements, seeded dice, finite resources, Bandit, bank and accepted player trades, 15-VP win condition, and portable deterministic event replay. Advanced cards, Knights and Invasion arrive in later stages.

## Build on Nox

```sh
flutter pub get
flutter analyze
buildq --wait -- flutter test
buildq --wait -- flutter build apk --release
```

Release APK: `build/app/outputs/flutter-apk/app-release.apk` (local testing only). Package ID `nz.presley.stoneandbanner`. No network, account or analytics features in Stage 2. Use Copy replay / Import replay for reproducible portable match logs. Use Nox Waydroid for Android testing; do not require Glass.

Gameplay legality, scoring and deterministic event/replay logic belongs in `lib/engine/`, never widgets. See `docs/ROADMAP.md`, `docs/RULES.md`, `docs/GLOSSARY.md`, and `docs/IP.md`. Do not publish before original-art, legal and security review.

The legacy Stage 1 Kotlin prototype remains on the powered-off Glass machine; Nox is canonical for all new work. The behaviour of its engine and UI preview was ported from an inspection of the original files.
