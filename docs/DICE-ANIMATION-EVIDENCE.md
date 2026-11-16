# Dice animation validation — 16 November 2026

The local Roll dice action opens a blocking 1.8-second presentation with two
shaded pip dice, opposing rotations, bounce, and a settled pair/total reveal.
It closes automatically before submitting the original engine-derived event.
Reduced-motion mode submits immediately. State changes or disposal during the
presentation prevent stale submission. No random generator or engine rule changed.
LAN rolls retain server authority: the presentation shows no claimed result
before the request is submitted, then the board displays the server's total.

Validation on the current checkout:

- pueue 6099: four tests passed, including the new supplied-result/reveal/close
  test and the existing full placement draft and seeded roll widget test.
- pueue 6096: `flutter build apk --release` passed.
- pueue 6092: `flutter analyze` reported 21 informational Material import
  deprecations in existing test files. pueue 6098 with `--no-fatal-infos` passed.
- Full `flutter test` attempted in pueue 6093; serial retry 6097 ended with
  146 passed and 83 failed. Failures include Flutter scheduler callbacks from
  `RelayoutWhenSystemFontsChangeMixin._scheduleSystemFontsUpdate` surviving
  widget teardown in unrelated card/tabletop flows. Full-suite validation
  remains incomplete; these failures were not suppressed or fixed here.
- Release installed and launched in isolated, headless Android API 35 emulator
  `emulator-5580`, with the new-match private handoff observed. AndroidRuntime
  and Flutter error log filters returned no lines. Screenshot:
  `evidence/dice-animation/emulator-release.png`. This is a launch smoke check;
  animation timing/result validation used widget tests, not physical hardware.

No public release or network service was deployed.
