# Stage 4 verification — Nox, 28 October 2026 (NZDT)

- Canonical source: Nox `/home/brandon/stone-and-banner`, Flutter/Dart, package `nz.presley.stoneandbanner`. Pre-edit main was clean at `1263e4b`.
- buildq `#1632`: `flutter analyze` passed, zero issues.
- buildq `#1633`: complete `flutter test` suite passed, including Stage 4 pure reducer/card physics, deterministic natural acquisition/export/import replay, 30,000 event samples, and two picker widget tests.
- buildq `#1634`: `flutter build apk --release` passed; APK at `build/app/outputs/flutter-apk/app-release.apk`, 51,063,033 bytes.
- Nox Waydroid connected over ADB `192.168.240.2:5555`: `adb install -r` returned `Success`; `am start -W -n nz.presley.stoneandbanner/.MainActivity` returned `Status: ok` and `LaunchState: COLD`; Android `dumpsys activity` reported `.MainActivity` resumed and visible with a live app process.
- In the actual release UI, navigated Home → Start match → handoff → complete 3-seat snake setup (six Village/Road pairs) → Roll dice → action phase. Screenshot `docs/evidence/stage4_waydroid_actions.png` shows the original Material 3 board and Strategy hand (0/4, Governance event 3/tier 3, zero eligible at undeveloped levels).
- Card detail/target selection/consumption/discard were tested via `flutter_test`; no claim of a live Android card play is made. No physical Samsung test was attempted in Stage 4.
