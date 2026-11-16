# Invasion feedback — 16 November 2026

Failed invasions already damage a Town/Capital or consume its Fortification.
When every settlement is a Village, there is no eligible target and no damage.
The existing outcome was available only in Realm details. Numerical rules,
seeded outcomes and event accounting are unchanged.

The engine now exposes an immutable forecast using the same resolver as the
recorded event. Build shows the expected result; emergency responders can
expand the forecast before spending aid. Resolution opens a dismissible result
dialog that survives subsequent turns. Reports explain Village safety,
Fortification loss, downgrade and VP loss, Governance protection, or Honour.

Validation uses the current checked-out repository and its pinned Flutter SDK.
Other sessions were editing this checkout concurrently; their changes were
preserved. Commit 77857b0 from another session captured the initial MatchView
wiring while this task was underway; this change supplies the referenced engine
method and feedback widget, plus the aid forecast.

- Pueue 6131: analyze with `--no-fatal-infos`, 17 focused tests, release APK.
  Analyzer has Material import deprecation infos from the current SDK.
- Focused tests cover no-target resource preservation, forecast/resolution
  agreement for damage, shields and Honour, replay/conservation regressions,
  aid/pass progression and persistent, dismissible feedback.
- Full `flutter test` was attempted (6120), and retried serially (6125):
  154 passed, 83 failed. Failures report Flutter's
  `RelayoutWhenSystemFontsChangeMixin._scheduleSystemFontsUpdate` transient
  callback remaining at teardown, including unrelated strategy-card flows.
  These runs are not a passing full-suite gate.

Release QA used a separate, headless, read-only Android 15 emulator instance,
`emulator-5586` (`sdk_gphone64_x86_64`), not the other running emulator or any
physical device. Installed the release APK with SHA-256
`fd4abbe8f080ad34ba9d372d35b7d4e54d7bda7e03cda99259110b4eb1eaff58`.
Imported the existing Stage 5 invasion fixture, passed Cora's aid, resumed Ada,
and viewed the forecast. In the final APK, tapped Resolve Invasion, observed
“Invasion resolved” with the Village-safe explanation, then tapped Continue.
The dialog closed, fleet pressure showed 0/3, and Roll dice was available.

Visually reviewed `forecast.png`, `result.png` and `after-continue.png` under
`docs/evidence/invasion-feedback-20261116/`: text legible, result fits, Continue
accessible, no overflow. The compact action panel requires scrolling to read
the full forecast. `validation.json` records the successful final Pueue task;
`logcat.txt` contains the filtered emulator error log.
