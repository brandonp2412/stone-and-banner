# Stone & Banner slice 06 — AI turn coordinator

Environment: Glass /home/brandon/stone-and-banner, offline Dart/Flutter; Waydroid 192.168.240.112:5555, 1792×1008. No Samsung or public deploy.

Files: lib/engine/ai_turn_coordinator.dart; lib/main.dart; lib/ui/match_screen.dart; test/ai_turn_coordinator_test.dart; test/ai_turn_coordinator_widget_test.dart; docs/E2E-AUDIT.md; test/goldens/home.png.

Validation:
- buildq #4781: pure coordinator tests PASS.
- buildq #4796: initial widget integration PASS (prior UI).
- buildq #4808: all 116 tests PASS (prior to concurrent setup UI).
- buildq #4809: focused analyzer PASS.
- buildq #4810: Linux runner release APK build PASS, installed on Glass Waydroid.
- buildq #4818: home golden update PASS (prior concurrent setup UI).
- buildq #4833: adapted coordinator widget tests PASS against concurrent latest setup UI.

Screenshots: 21 timestamped PNGs, all visually inspected; SCREENSHOT-MANIFEST.md has an action/expected/actual/verdict row per screenshot. Screenshot 08 was premature; screenshots 09/10 establish action result. Screenshot 16 shows compact choice sheet; screenshot 20 shows AI progress; 21 shows handoff. Human action controls screenshot 19 still dense.

Guardrails: no external AI, backend, Riverpod/go_router; deterministic replay events; cancellation invalidates stale asynchronous steps and prevents double-spend; no UI secrets exposed during AI turn.

Concurrent changes: another slice added 1/2 AI selector to lib/main.dart and test/ai_setup_widget_test.dart while this slice ran. Do not remove that work; tests were adapted to it. .serena and test/failures are untracked incidental files, not owned by this slice.

Final verification: buildq #4835 home golden refresh PASS; #4836 entire Flutter test suite PASS; git diff --check PASS; commit ba398d0 on main. Concurrent test/ai_setup_widget_test.dart and incidental .serena/, test/failures/ remain untracked and untouched.
