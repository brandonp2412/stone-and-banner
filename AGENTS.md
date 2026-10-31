# Project instructions

- Use the current checked-out repository. Do not depend on or wake unrelated machines.
- Flutter/Dart Material 3 only; pure immutable Dart rules under `lib/engine/`. Generated Kotlin Android host is allowed, not Compose game/UI code. Package ID `nz.presley.stoneandbanner`.
- Read `docs/ROADMAP.md`, `docs/RULES.md`, current git state and previous stage evidence before edits. Preserve others' edits. Stay offline-first; use no Riverpod or go_router.
- Use `buildq` for heavy tests/builds where available; verify `flutter analyze`, `flutter test`, `flutter build apk --release`. Test releases in an isolated Android emulator. Only claim physical-device testing when actually observed.
- All randomness must come from saved deterministic seeds/events, no UI decisions about legality. Keep replay accounting and property tests. No Catan intellectual property, copied artwork or text.
- Commit validated work on main. No public store release or paid server without explicit permission.
