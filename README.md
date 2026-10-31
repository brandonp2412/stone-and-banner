# Stone & Banner

Original offline-first Android strategy game built in **Flutter/Dart**. The app provides a playable 3–4-seat pass-and-play match: 19 hexes, legal roads and settlements, seeded dice, finite resources, Bandit, bank and accepted player trades, 15-VP win condition, and portable deterministic event replay. Town Developments, Knights, Invasion, three Strategy Card decks, standing escrowed trades and tactical out-of-turn reactions are implemented.

## Build and test

```sh
flutter pub get
flutter analyze
buildq --wait -- flutter test
buildq --wait -- flutter build apk --release
```

Release APK: `build/app/outputs/flutter-apk/app-release.apk` (local testing only). Package ID `nz.presley.stoneandbanner`. No network, account or analytics service is required for local play. Local matches autosave as private on-device replays and can be resumed through a handoff screen; Both raw JSON and compact replay codes expose all players' hidden hands, so share only with trusted participants. Use Copy replay or compact share codes with Import replay for reproducible portable match logs. Use an isolated Waydroid emulator for Android testing; do not require another machine.

Gameplay legality, scoring and deterministic event/replay logic belongs in `lib/engine/`, never widgets. See `docs/ROADMAP.md`, `docs/RULES.md`, `docs/GLOSSARY.md`, and `docs/IP.md`. Do not publish before original-art, legal and security review.

Flutter/Dart sources in this repository are canonical. Obsolete Kotlin/Compose source is not part of the Flutter game.

## LAN multiplayer

Set `LAN_BIND_IP` to your trusted host interface address, then run `dart run tool/lan_server.dart --bind "$LAN_BIND_IP" --port 8765`. Open **LAN multiplayer room** on each Android device to create/join a 3–4-seat room and resume by seat token. No public remote multiplayer backend is deployed; offline pass-and-play still works without any server. See `docs/STAGE6.md` for trust, secrecy, timeout policy and limitations.


## Stage 8 local release candidate

Version 0.8.0+8. Original generated Stone-and-Banner crest ships as the app launcher icon and home artwork. Screen readers can select legal junctions, roads and Bandit hexes through **Choose board target from list**; the board remains pinch-zoomable. Automatic replay saves survive ordinary app restarts and never skip a private seat handoff. Android backups are disabled because local saves contain hidden hands. APKs built with the repository default debug signing key are **for local emulator testing only**; production key custody, secure LAN transport, broader user/accessibility sessions and independent IP/privacy/security approval are still required before distribution.
