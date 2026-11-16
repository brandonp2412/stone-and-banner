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

## NVIDIA clipping follow-up — live Wayland proof

The first desktop change did not fix the user's black/clipped window. The Xvfb test above bypassed the affected NVIDIA path. The existing debug process was reproduced and captured in the actual dwl session: `evidence/desktop/nvidia/before-native-debug.png` (898×1080, approximately 74% black pixels).

The installed Flutter 3.50.0 engine source explains the matching clipping: `fl_opengl_manager.cc` disables framebuffer blitting for NVIDIA; `fl_compositor_opengl.cc` then applies a full-layer offset of (-1,-1), while `fl_compositor_opengl_shader.cc` already defines vertices from -1 to +1. The shader fallback shifts the frame into the lower-left quarter. XWayland on the same GPU also reproduced the failure, so switching window backends was discarded.

The committed workaround is confined to `linux/runner/main.cc`: when `/proc/driver/nvidia/version` exists, default `FLUTTER_LINUX_RENDERER` to `software` before creating GTK/Flutter objects. An existing explicit renderer value is respected. Native Wayland remains available. This is CPU rasterization on hosts with the proprietary NVIDIA driver, including hybrid hosts with that driver present; graphics acceleration and long-session frame pacing are not claimed. No Flutter SDK or system driver was modified.

### Proof actually observed

- Rebuilt Linux **debug and release** (#6081). The debug build with the automatic fallback filled a real **1920×1080 dwl output on this RTX 4090 host**, captured with `grim`: `nvidia/debug-home-1920.png`. Test-only title/fullscreen instrumentation was used for that capture and subsequently removed; the final host change contains only renderer selection.
- Ran the final release binary in a separate native Wayland Cage compositor on the same host (#6083), with `GDK_BACKEND=wayland`, an isolated XDG data directory, and **no `FLUTTER_LINUX_RENDERER` override**. The app selected software rendering itself, as shown by its engine log.
- Changed the live headless output with `wlr-randr --output HEADLESS-1 --custom-mode WIDTHxHEIGHT@60Hz`: **1280×720 → 1920×1080 → 1280×720 → 1920×1080**. Inspected the resulting Home frames after settling; the app filled each window without clipping. Files: `release-native-1280.png`, `release-native-1920.png`, `release-native-resized-back-1280.png`, `release-native-resize-1920-again.png`.
- Used keyboard navigation on the isolated compositor to open rules, return Home, open New local match, activate Start match and clear the private handoff. Inspected setup and the full board at 1920×1080: `release-native-setup.png`, `release-native-board-1920.png`. Then resized the **same running match** to 1280×720 and back to 1920×1080 and inspected both frames: `release-native-board-resized-1280.png`, `release-native-board-restored-1920.png`. No gameplay state was injected.
- `nvidia/captures.json` records image sizes, SHA-256 hashes, and black-pixel fractions. All post-fix frames have zero near-black pixels under the recorded threshold, versus approximately 74% before. Pixel counts supplement visual review; they are not a general rendering correctness test.

Shared-session test windows were marked with the hidden sentinel, but some mapped visibly/focused despite that marker; those test processes were closed. Remaining interaction and resize checks were moved to the isolated headless Wayland compositor. The original user's running debug process was left alone. A **full process restart** is required to apply this native host change; hot reload cannot apply it.

Analyzer and the desktop regression test passed with the existing deprecation infos (#6063). The full suite was also attempted (#6071); it failed with font-callback errors and an in-progress concurrent mobile-panel test failure. The repeat run (#6091) finished with 146 passed and 83 failed, with the font-callback failures still present. No full-suite pass is claimed. Earlier Android release/emulator evidence remains applicable: this follow-up changes only the Linux host.
