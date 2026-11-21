# Completion 1/8 — exact build and handoff

Source worktree: `/home/brandon/worktrees/stone-mobile-actions-20261105` on Glass, branch `feature/mobile-actions-20261105`, based on reconciled evidence commit `f35dd33` (parent origin/main `f36c843`). The original Glass `main` remains dirty and untouched. Its unfinished `match_screen.dart` and `stage5_widget_test.dart` changes were ported by reviewed three-way merge, resolving a Knight-chip conflict without modifying the original files.

## Implemented and verified

- Mobile actions precede the board; phase-appropriate Roll/Resolve/End controls are prominent and scroll position resets on phase/seat transition.
- Unaffordable build chips and unavailable Knight choices are absent rather than disabled; inspect stays available; trade entry points are visible and placed side by side at 390 px.
- Existing unfinished focused bank/standing-trade routes were incorporated, with stock/escrow reducer tests; cards/development/Knight panels and tactical privacy remain accessible.
- No game-engine rules, seeded events, replay semantics, external services, Riverpod, or go_router were added.

| Glass buildq | Result |
| --- | --- |
| `#4991` | 14 focused widget/accessibility tests passed on first panel draft |
| `#4992` | Full `flutter analyze lib test tool`: clean |
| `#4994` | Initial release APK built |
| `#4993`, `#4995` | Full tests found an invasion-to-roll scroll regression, fixed by phase-change scroll reset |
| `#4997` | Focused invasion test passed after fix |
| `#4998` | Headless Linux release built; Home screenshot only, not action-screen E2E |
| `#4999` | Full 142 tests passed before compact trade-row adjustment |
| `#5000` | Analyzer clean |
| `#5001` | Release APK built before compact adjustment |
| `#5003` | New narrow-screen trade-row assertion initially failed, revealing button wrapping |
| `#5004` | All 8 focused Stage-5 widget tests passed after fixed-width row |
| `#5005` | **Final 142 Flutter tests passed** |
| `#5006` | **Final analyzer clean**, `lib test tool` |
| `#5007` | **Final Android release APK built** (54,955,834 bytes; SHA-256 `e1766c0c7a153396b6b5527a6f2870cea022a110c5362d036c58cd2c15c41204`) |
| `#5008` | Separate QA-ID APK built, installed on Nox Waydroid user 11 (SHA-256 `5f5ce05dfda7500d0e4ee5dd117d197cefadbe8d871a9909fc4d0db51ad78617`) |

Source commits: `fa3e8f63f8fd6d3039090fe8bf8e89c8378a6fad` and `353c8aa` (full SHA recorded by Git). Evidence in [screenshot manifest](SCREENSHOT-MANIFEST.md) and [comparison](comparison-before-after.png). No Samsung install, public release, main mutation or Prompta jobs.

## Unresolved

- Glass Waydroid was in use by Instagram/SloppaTV; only Nox Waydroid real 390 × 844 interaction is claimed.
- The old Nox release was signed with a different key (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`); it was preserved. QA variant differs only in application ID/label, compiled from matching source files; install/resume succeeded.
- Complete natural human gameplay, legal build execution on Android, strategy/trade/reaction interaction and larger-text Android acceptance remain to subsequent completion slices.
- Glass main is behind origin and contains other unfinished dirty edits; this feature was isolated and must not be merged over the reconciliation owner. No main push in this slice.
