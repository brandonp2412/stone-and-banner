# Slice 08 — screenshot/action manifest (4 November 2026, NZDT)

**Actual Linux/Waydroid app screens opened: none. Meaningful live UI interactions: none. Actual device screenshots: zero.** This is a pure Dart AI stability/fairness slice. No Samsung device, deployment, or public service was touched. Therefore no immediate-after-navigation/action live screenshot or live-app visual verdict can honestly be claimed.

| Live action / navigation | Expected | Actual | Live screenshot | Visual verdict |
| --- | --- | --- | --- | --- |
| None (no live UI opened) | Engine-only seeded matches | No live UI interaction | None / not applicable | Not applicable |

## Supplementary Flutter golden-test diagnostic — **not live-device screenshots**

The existing `test/visual_test.dart` failed at its first Home golden after concurrent, uncommitted `lib/main.dart` added the AI toggle. Flutter's own widget-test compare PNGs were preserved under `golden-failure/` here:

- `golden-failure/home_masterImage.png` — original expected Home.
- `golden-failure/home_testImage.png` — rendered Home with new "Play against computer" row.
- `golden-failure/home_isolatedDiff.png` and `golden-failure/home_maskedDiff.png` — framework-generated differences.

The master, actual, and isolated diff images were **visually inspected**. At 390×844, the added row pushes the "Start match" button behind the bottom navigation; the lower form is clipped, harming hierarchy and touch access. Contrast and type above that point are legible. This is a genuine uncommitted UI regression owned by an overlapping AI UI slice, so Slice 08 did not modify that work, regenerate goldens, or claim the issue fixed. An actual Linux/Waydroid app run plus per-action screenshots and correction remain necessary for UI acceptance.

The concurrently updated `test/goldens/home.png` was subsequently visually inspected. It matches the added toggle layout but **still places the start button behind bottom navigation**; `buildq #4814` passed after golden rebaselining. Passing the golden is not proof of acceptable layout.
