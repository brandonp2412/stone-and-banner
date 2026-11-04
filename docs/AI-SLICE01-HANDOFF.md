# Stone & Banner — Slice 01/20 factual handoff

**Local window:** 4 November 2026, approximately 17:56–18:15 NZDT (inside the 45-minute hard limit). **Host:** Glass. **Repository:** /home/brandon/stone-and-banner. **Baseline:** clean main at 526ccfc, matching origin/main before edits; only one worktree, no untracked user changes at start. Read /home/brandon/AGENTS.md, project AGENTS.md, docs/ROADMAP.md, docs/RULES.md and docs/STAGE8-EVIDENCE.md before edits.

## Outcome

- Added docs/AI-ACCEPTANCE-MATRIX.md: current bot/engine/UI/LAN inventory, exact AI acceptance requirements, all meaningful screen and reducer feature rows, proposed deterministic API boundaries, and explicit Linux/Waydroid interaction plans.
- Added docs/evidence/ai_slice01/SCREENSHOT-MANIFEST.md and timestamped PNGs for **14 actual UI navigation/action captures** (one unsuccessful launch attempt, 13 successful captures). Each row records the action, expected, actual and visual verdict.
- Verified a live Waydroid 3-seat match: Home → Rules → Board empty → create → private handoff → Village at Junction 1 → legal Road → Player 2 handoff. Score changed to 1/15 and phase advanced to setupRoad; Player 2 board showed previous pieces.
- Rebuilt release APK using the pinned project Flutter SDK and a command-scoped JDK 17 override, reinstalled on Waydroid, then verified saved match resumed behind a private Player 2 handoff with previous Village/Road intact.
- **No AI opponent was implemented or run**. Stage 2 will build the mixed-seat controller and policy. No Linux desktop UI session, LAN socket session, entire-match victory flow, physical device, accessibility assistive-technology session or offline network-disconnect test was executed in this slice. **Samsung untouched.**
- **No game/UI Dart source changed**; existing gameplay and Stage 8 release gates preserved.

## Actual commands and outcomes

| Command (run on Glass) | Result |
| --- | --- |
| git status --short --branch; git log -4 --oneline; git worktree list | Clean main at 526ccfc; one worktree. |
| flutter --version | Global wrapper exposed Flutter 3.49.0-0.1.pre, Dart 3.13.4. |
| buildq --label stone-ai-slice01-fasttests -- flutter test test/balance_simulation_test.dart test/match_test.dart test/widget_test.dart test/visual_test.dart | **#4710 FAIL pre-compile:** pubspec requires SDK ^3.13.5. |
| buildq --label stone-ai-slice01-analyze -- flutter analyze lib test | **#4711 FAIL pre-analysis:** same SDK incompatibility. |
| /home/brandon/.local/share/flutter-stone-and-banner-3.47.6/bin/flutter --version | Project-local Flutter 3.47.6, Dart 3.13.5, compatible with existing .dart_tool/package_config.json. |
| buildq --label stone-ai-slice01-tests-sdk3135 -- /home/brandon/.local/share/flutter-stone-and-banner-3.47.6/bin/flutter test --no-pub test/balance_simulation_test.dart test/match_test.dart test/widget_test.dart test/visual_test.dart | **#4712 PASS:** 20 tests. |
| buildq --label stone-ai-slice01-analyze-sdk3135 -- /home/brandon/.local/share/flutter-stone-and-banner-3.47.6/bin/flutter analyze --no-pub lib test | **#4713 PASS:** No issues found. |
| buildq --label stone-ai-slice01-full-suite -- /home/brandon/.local/share/flutter-stone-and-banner-3.47.6/bin/flutter test --no-pub test | **#4714 PASS:** 71 tests. |
| buildq --label stone-ai-slice01-release-check -- /home/brandon/.local/share/flutter-stone-and-banner-3.47.6/bin/flutter build apk --release --no-pub | **#4715 FAIL:** android/gradle.properties pins missing /usr/lib/jvm/java-21-openjdk. |
| buildq --label stone-ai-slice01-release-jdk17 -- env GRADLE_OPTS=-Dorg.gradle.java.home=/usr/lib/jvm/java-17-openjdk JAVA_HOME=/usr/lib/jvm/java-17-openjdk /home/brandon/.local/share/flutter-stone-and-banner-3.47.6/bin/flutter build apk --release --no-pub | **#4716 PASS:** 54.4 MB release APK. SDK XML version warning, not build-fatal. |
| /opt/android-sdk/build-tools/37.0.0/apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk | **PASS:** V2 signer CN=Brandon Presley; JDK restricted-native-access warnings, no signature verification failure. |
| adb -s 192.168.240.112:5555 install -r build/app/outputs/flutter-apk/app-release.apk | Success after #4716; installed only to Glass Waydroid. |
| adb -s 192.168.240.112:5555 shell am start -n nz.presley.stoneandbanner/.MainActivity | Success. Private saved-match restore and board interaction observed. |
| adb -s 192.168.240.112:5555 shell input tap X Y and screencap -p followed by adb pull after every interaction | Screenshot per action in docs/evidence/ai_slice01; visual verdict in manifest. |

**Release APK:** /home/brandon/stone-and-banner/build/app/outputs/flutter-apk/app-release.apk, 54,398,538 bytes, rebuilt SHA-256 **3f57b11e25d17e00780a2a1ceb8348a8f169831c603f38ee6d7340a43f4df372**. Initial installed binary had same size but different SHA-256 **360ab294347987cd7011e40a1d1365b8663aa7bde564aaac590e6ef2075166d2**; the manifest distinguishes before/after. Android apksigner **verified V2 signature** with signer DN **CN=Brandon Presley** and certificate SHA-256 **011ee1a6e4e5ecd675f67fbf3d78ad82614a7a7a3f24ed71cc9c417154a0f0fd**. This differs from the older Stage 8 evidence (Android Debug); certificate provenance and release authorization are not established. This remains a **local test artifact, not approved for publication**.

## Observed visual verdict

- **Home:** coherent dark Material 3, clear Start and resume states. Wide landscape content is a narrow central column; supporting action copy appears small.
- **Rules:** readable high-contrast content, but several dense paragraphs lack progressive disclosure.
- **Empty Board:** single clear Create a match button.
- **Setup Board:** distinctive high-contrast hex map and glowing legal targets; the state/score and required move update correctly after placement. Small phase/instruction labels on wide landscape.
- **Target sheet:** accessible textual alternative to precise board tapping, but a long ungrouped list; grouping/filtering may help.
- **Handoffs:** single action, no private hand/board visible, works after APK replacement and replay restore.

No visual change was made in this baseline slice. The test was actual Waydroid 1792x1008 landscape, not a screenshot mockup or widget golden. Portrait, Linux desktop layout, large text and TalkBack remain to be exercised later.

## Next slice — blockers and gaps

1. **Core 2-seat prerequisite:** MatchEngine.newGame accepts only 3/4 seats; strict 1 human + 1 AI acceptance needs a tested 2-seat snake draft/round path. One human + two bots alone is not enough.
2. **AI policy isolation:** BalanceSimulation.run is an all-bot batch harness with full MatchState. Extract a per-seat deterministic policy that sees public state plus *only its own* hand. Existing fair legal action claims in the harness do not certify hidden-information fairness of a new UI bot.
3. **AI turn controller/UI:** mixed seat-kind setup, AI-turn status, no bot handoff, serialized dispatch, autosave/resume, bounded invalid/stalled decision fallback, no network.
4. **Test acceptance:** two-seat and mixed-seat properties, many-seed legal/conservation/replay tests, hidden-hand perturbation, timeout/fault injection, and both Linux/Waydroid end-to-end screenshots. A full AI match to 15 VP remains unexecuted.
5. **Host build hygiene:** global Flutter exposes Dart 3.13.4 despite repo minimum 3.13.5; project-local SDK works. Android Gradle property pins a missing JDK 21, so a command-scoped JDK 17 override was required. This slice did **not** alter shared toolchain or Gradle project files; future builds must use the command above or separately repair the pin after checking other consumers.
6. **Release gates:** Stage 8 remains unchecked (signing key provenance/approval, security/privacy/IP, real-device accessibility, multiplayer transport/adversarial audit, human balance). No network host, proprietary API, store upload or Samsung install.

**Evidence entry points:** docs/AI-ACCEPTANCE-MATRIX.md and docs/evidence/ai_slice01/SCREENSHOT-MANIFEST.md. Existing historical Stage 8 evidence is not silently promoted to new tests.
