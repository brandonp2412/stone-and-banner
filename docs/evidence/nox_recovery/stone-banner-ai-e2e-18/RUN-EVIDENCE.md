# Stone & Banner — slice 18/20 implementation, builds and QA (4 Nov 2026 NZDT)

## Code changes
- Responsive Home setup controls switch from segmented groups to wrapping ChoiceChips below 360 px or above 1.35× text scale. Setup title Flex no longer overflows at 320 px / 1.6× or 390 px / 2.0×.
- First-screen New local match call to action moved above description, reachable in smaller or magnified layouts.
- Each main page uses a distinct keyed scroll subtree to prevent preserved offset hiding the Rules title after navigating from setup.
- Root Focus handles Escape for secondary pages and routes (using Navigator.maybePop), preserving dialog and match handoff PopScope rules.
- Match actions now prioritise a full-width End turn button; bank/player trades wrap to minimum 48 px touch-height controls; Knights & defence and Town Developments are separate collapsed expandable groups.
- Updated game-action widget tests to open secondary expansion panels, added six focused accessibility/navigation/widget-size tests, updated changed Home golden.

## Verified checks (Nox buildq)
- #4561 Home/playable-board/Rules golden update + test: PASS (one test).
- #4562 full flutter test test/ --reporter expanded: **PASS, 137 tests**.
- #4566 flutter analyze: **PASS, zero issues**. Prior #4563 observed one curly-brace lint and was corrected, never counted as clean.
- #4564 flutter build linux --release: PASS, build/linux/x64/release/bundle/stone_and_banner.
- #4565 flutter build apk --release with JDK 21 override: PASS, 54.9 MB build/app/outputs/flutter-apk/app-release.apk; **not installed**, no Samsung or public release.
- Additional directly run tests: 6/6 new targeted tests and 2/2 advanced widget tests passed.
- git diff --check: PASS. The clean analyzer was run after the final brace-only edit; full tests and builds preceded that lint-only edit.

## Real GUI observations and verdict
- [33 screenshot/action rows](SCREENSHOT-MANIFEST.md), images 001–033 retained, all reviewed; separately [structured JSON record](reviewed_actions.json).
- Desktop isolated Linux Xvfb (1280×800) Home, setup, Vs AI, Rules, hover, keyboard focus; isolated 390×844 Linux desktop viewport Home/setup/Vs AI/Rules/Board-empty and Escape. Verified Rules heading stays visible, Escape returns Home, no overflow at 390.
- Initial Escape defect confirmed in screenshot 015 before fix; retested PASS in 027. Initial oversized 390 px windows and contested :119 X display retained as FAIL/LIMITED frames; repeated on verified free X display :191.
- Existing Waydroid user 11 was already active; one screenshot 007 taken **read-only**, no UI action. It is an older build and cannot demonstrate current UI fixes.
- Attempted dark GTK / 1.4× DPI Linux renders are **byte-identical** to normal-light 390 screenshots; dark theme/large text screenshot proof is **not achieved**. Flutter widget tests cover exact 320×640 at 1.6× light, 390×844 at 2.0× dark, 1024×768 at 1× light.
- Keyboard Tab changes focused surface, but visible focus indication remains subtle. No actual touch-target measurement or screenreader/TalkBack test. Secondary match action UI not reopened in live gameplay during this slice; focused widget coverage and builds are evidence, not a substitute for full device QA.
- No Android installation, Samsung, network hosting, public release or external online service. No interleaved app UI changes on in-use Waydroid user 11.

## Final attempted match-screen screenshot (not claimed as success)

- After committing, tried fresh isolated Xvfb displays :193 and :194 to open release and screenshot the revised match actions. Flutter started and logged Impeller/GDK warnings, but no visible application window could be resolved by xdotool. **No app screen or UI action was opened/performed in those attempts, thus no screenshots from them.** Logs retained as `linux-board-e2e.log`, `linux-board2.log`, `xvfb-board.log`, `xvfb-board2.log`. This does not count as match-screen E2E proof. All prior 33 captured actions remain preserved in the manifest.
