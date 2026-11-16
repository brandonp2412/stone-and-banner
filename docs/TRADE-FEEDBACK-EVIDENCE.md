# Trade response feedback — 16 November 2026

Standing trades now show their latest recorded acceptance or decline in the
Trade panel, including public terms and the recipient's name. Declines explain
that reserved goods were returned. Newly recorded responses also show a
notification. Pending outgoing offers explain that recipients answer during
their action turn. Expiry and withdrawal are not inferred to be rejection.
Feedback is derived from replay events; no engine rules or AI choices changed.

Validation in this checkout:

- Pueue 6106: four trade feedback tests passed (decline, acceptance, withdrawal,
  notification and persistent panel result).
- Pueue 6113: 19 focused trade/AI reaction tests passed.
- Pueue 6109: release APK built successfully.
- Installed and launched that APK on isolated, headless Android emulator
  emulator-5582 (stone_design_api35, read-only disk). Home rendered successfully;
  screenshot: evidence/trade-feedback/release-home.png. No AndroidRuntime or
  Flutter error output was observed. Trade response interaction was verified
  by widget tests, not by manual Android interaction. No physical-device test.
- Full suite attempted (6107): 151 passed, 83 failed, with repeated SDK
  RelayoutWhenSystemFontsChangeMixin transient callback failures after widget
  disposal. The SDK was being bootstrapped/changed concurrently in this shared
  checkout. These failures remain unresolved here.
- Standard analyze attempted (6108): SDK Material import deprecation infos.
  Analyze with --no-fatal-infos (6114) completed successfully, reporting 24
  informational deprecations. No claim of a clean standard analyzer/full suite.

Other concurrent checkout changes were preserved.
