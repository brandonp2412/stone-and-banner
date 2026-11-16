# Desktop layout verification — 16 November 2026

Changes use the current checkout and retain the deterministic rules unchanged.

- At widths of at least 1200 and home heights of at least 650, Home has a framed crest, separate menu column, and save information. Smaller windows retain the compact layout.
- Desktop setup is centered and capped at 1100×640, with scrolling options and an anchored Start button.
- Large match windows give the action panel 25% of the width, bounded to 320–420 pixels, while the map fills the remaining space.
- The root page Stack explicitly fills the available viewport.
- Linux uses Skia. A release build using this SDK's Impeller backend showed a hard horizontal discontinuity in the crest gradient in an isolated X11 display; the Skia release rendered it correctly. This does not establish the cause of the user's original Wayland black regions.

## Checks

Pueue #6056 runs analyzer, desktop regression test, Android release build and Linux release build. Analyzer has no errors or warnings but reports 19 Material import deprecation infos with Flutter 3.50.0 / Dart 3.14.0; `--no-fatal-infos` is needed for a successful exit. Ordinary `flutter analyze` was also run (#6045) and returned those infos.

`test/desktop_layout_test.dart` checks the 1920×1080 page bounds, visible menu controls, setup width, entry to a large match map, and resizing to 844×390. It passed independently (#6052) and in #6056.

The full `flutter test` run (#6046) finished with 142 passes and 83 failures. Existing font-loading tests fail with `An animation is still running even after the widget tree was disposed`, from `RelayoutWhenSystemFontsChangeMixin._scheduleSystemFontsUpdate`. The compact tabletop suite also reproduced this (#6048). Full-suite validation remains incomplete; no unrelated test or SDK changes were made to suppress it.

## Live release checks

Linux release launched on isolated Xvfb display :93 using X11, Mesa software rendering and a separate XDG data directory. Resized to 1920×1080; visually inspected Home, bounded setup, private handoff and the board. `evidence/desktop/linux-home-1920.png` shows the corrected gradient; `linux-setup-1920.png` and `linux-board-1920.png` capture the final setup and match layouts. This was not a test of the user's active Wayland session or physical GPU.

Android release installed only on isolated, headless AVD `stone_design_api35`, serial `emulator-5584`, launched read-only with no snapshot writes. Overridden to 1920×1080 / 160 dpi. Checked Home, setup, replacement confirmation and private handoff; chose a legal junction from the target list and observed Player 1 gain 1 VP and the phase change to Road. Screenshot: `evidence/desktop/android-placement-1920.png`. Reinstalled the final APK and verified cold launch. No physical-device testing. No AndroidRuntime or Flutter error lines appeared in the emulator log check.

No store publication, public server, network service, or unrelated machine was used. Existing user edits were preserved.
