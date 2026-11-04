# Slice 10/20 — cross-platform screenshot harness and live QA

4 November 2026 NZDT · Glass only · independent of predecessor handoffs.

## Delivered

- Reusable standard-library harness: 'tool/e2e_screenshot_harness.py'.
  Hosts: Glass or Nox; targets: isolated Wayland Linux desktop via grim/wtype
  or Android Waydroid via adb screencap/input. It rejects non-Waydroid
  Android models, including the connected Samsung, and refuses a mismatch
  between session host and actual hostname.
- Collision-resistant full-resolution PNG filenames, real UTC/NZ timestamps,
  app version, executable/APK code fingerprint, host/device/display tag,
  semantic action and raw key/coordinate log, expected and actual state,
  critique, severity, retest ID, and append-only JSONL review events.
  'complete' requires a screen-open, action and all frames reviewed; 'verify'
  checks PNG chunk checksums, file names, dimensions and completed flows.
- [Protocol](../../../UI-E2E-PROTOCOL.md)
  (in repository 'docs/UI-E2E-PROTOCOL.md'); six no-device unit tests.
- Android capture launch changed from monkey (which exited 251) to explicit
  exported MainActivity after the failed attempt was recorded and visually
  inspected; new capture #2 proved the correction. The original failed
  screenshot remains in the manifest.

## Live screenshot matrix

| Target | Build and run | Screenshots, actually visually reviewed | Verified flows |
| --- | --- | --- | --- |
| Glass isolated Linux, headless cage/Wayland wayland-2, 1280×720 | Flutter 3.47.6, Dart 3.13.5; buildq #4852 isolated release; libapp.so SHA-256 d684cb0d4f35bf1d630e17a07e83343a17287bd2a6c3daa3e5cf95c0a6d1dab8 | **12**; [manifest](linux-glass/SCREENSHOT-MANIFEST.md), [session](linux-glass/session.json) | Home → Start match → private Player 1 handoff observed; private handoff → live Round 1 setup board **PASS**. Initial flow ID was named for a planned Rules route but actual route changed; marked **LIMITED** rather than claim a Rules visit. |
| Glass Waydroid x86_64 192.168.240.112:5555, Android user 0, 1792×1008 | Installed version 0.8.0, code 8; APK SHA-256 71e0847f9a81825a88b6470d3ac29dbb36bbc7140f0ddbf6ac0397d5032db3b7 (not the newly built APK) | **9**; [manifest](waydroid-glass/SCREENSHOT-MANIFEST.md), [session](waydroid-glass/session.json) | Home → Vs AI → four players → three AI options **PASS**; configured Home → Rules → Home with options preserved **PASS**. Initial monkey-launch failure #1 retested successfully #2. Final Home key restored Android launcher without touching saved game. |

Total **21 real PNGs**, all visually inspected; no fabricated Nox, Samsung, physical-device or full-game testing. Linux was headless and did not take the user's display focus. Android screen was untouched after restoring launcher.

The first ad-hoc Linux cage process exited on tool return, so an attempted grim capture failed before a file could be saved. We restarted this slice's own cage in a scoped user systemd service, correctly identified its live wayland-2 socket, then captured and reviewed every subsequent action. This initial failed diagnostic was **not** counted as a screenshot. It is not evidence of a UI test.

## Live visual review

- Linux Home: clear dark/gold hierarchy, generous card whitespace, readable primary CTA, aligned bottom navigation. Private handoff: centered lock, explicit next action, no hidden goods visible. Board: visible glowing setup junctions and 0/15 VP; lower board requires scrolling at 720px height.
- Linux keyboard focus: Tab traversal frames #2–#8 and #11 show no reliably discernible focus ring. Marked LIMITED/minor in individual reviews. The eventual Return actions demonstrably opened the private handoff and the board, but intermediate focus attribution remains unproven. No broad UI rewrite was made during concurrent changes.
- Waydroid Home: clear segmented selection feedback, visible 1-human/3-computer caption, no clipping. Existing APK shows an older, lengthy "Start new match (replaces saved match)" CTA, while current source uses a shorter label and separate warning. This is installed-build drift, not a verified regression in the current source.
- Waydroid Rules: all original-rule headings visible, but paragraphs visually dense/small at wide landscape resolution (minor). Return to Home preserved Vs AI, four players and three AI.
- First Android launcher screenshot (#1) was a real launch failure, severity major, followed by retest #2 showing the real app. No saved match was replaced. No fresh APK was installed onto shared Waydroid.

## Exact checks on Glass

| Command | Result |
| --- | --- |
| 'python3 -m unittest tool/test_e2e_screenshot_harness.py -v' | **6/6 pass** after correcting test fixtures and adding failed-input/launch coverage |
| Harness 'verify --require-flows 1' (Linux) | **12 reviewed PNGs**, 1 PASS flow; 1 LIMITED exploratory flow |
| Harness 'verify --require-flows 2' (Waydroid) | **9 reviewed PNGs**, 2 PASS flows; unique filenames/PNG checksum verified |
| 'buildq --label stone-ai10-isolated-linux-release -- flutter build linux --release' in isolated scaffold | **#4852 succeeded**, executable screenshot-tested |
| 'buildq --label stone-ai10-flutter-tests -- flutter test test/ --reporter expanded' | **#4869 succeeded, 122 tests passed**; checkout concurrently edited by other slices |
| 'buildq --label stone-ai10-flutter-analyze -- flutter analyze lib test tool' | **#4870 succeeded, no issues** |
| 'buildq --label stone-ai10-android-release -- flutter build apk --release' | **#4871 succeeded**, 54,791,918 bytes, SHA-256 7796f569839df62a394b41322046f95994a95fe2586b2681ab4ee5d3e45eb2fb; **built only, not installed** |

Current worktree included unrelated concurrent main.dart, widget test/golden and
.serena/test/failures changes. These were preserved and are not staged by this
slice. Source at verification had main HEAD fba552633bb2751e5284f678cbb7f805a7fdad89; the isolated Linux snapshot was copied while other local edits existed and is tagged as dirty, not claimed to be exactly that commit.

## Remaining gaps / handoff

1. Nox Linux and Nox Waydroid paths are documented but not run. Verify binaries,
   Wayland isolation and adb serial on Nox before any Nox PASS claim.
2. Keyboard focus feedback and dense landscape Rules text merit targeted
   accessibility/typography review after concurrent UI edits settle; retest
   with captured screenshots and severity IDs.
3. If an isolated fresh APK test environment becomes free, install the new
   release there and recapture its corrected saved-match CTA. Do not overwrite
   the current shared Waydroid installation or its saved replay without coordination.
4. The Android flow validated selection only, **not** starting or finishing a
   new 3-AI match. Linux started a hot-seat match, not a full victory. No
   external backend or LAN test occurred.
5. All Stage 8 signing, legal/IP, network security, accessibility/physical
   device and public distribution gates remain open. No public deployment.


## Final commit and cleanup

- Main commit: **126fe476adc7366366727133ce1ed7c85c2fd971** (four harness/protocol/audit files only).
- Stopped this slice's own transient headless service stone-ai10-cage.service after the screenshot run. No other compositor or Waydroid session was stopped.
- The unrelated concurrent uncommitted Flutter/widget/golden edits remain in the worktree; they were deliberately excluded from the commit.
