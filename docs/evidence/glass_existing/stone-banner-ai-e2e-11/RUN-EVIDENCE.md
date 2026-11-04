# Stone & Banner Slice 11/20 — Home, Rules, Match Setup

Date: 4 November 2026 (NZDT). Host: Glass. Evidence: [53-row screenshot manifest](SCREENSHOT-MANIFEST.md), all 53 PNGs saved in this directory and visually inspected individually.

## Scope and implementation

- Offline-first, deterministic Dart/Flutter Material 3. No cloud AI, backend, Riverpod, go_router, Samsung device, or public deployment.
- Home changed to focused landing with prominent **New local match**, optional **Continue saved match**, and quieter Rules/LAN/Replay destinations. Match options moved to a dedicated **Match setup** page with 3/4-seat and human/AI seat controls, advanced human names/seed disclosure, back navigation and numeric/name validation.
- Existing saved match is protected by an explicit overwrite confirmation. Rules has concise essentials and individually expandable advanced rules/glossary. Malformed replay error no longer includes raw parser exceptions or pasted replay code.
- Regression tests updated and added for Home/Rules navigation, 3/4-seat AI configuration, invalid seed/names, overwrite cancel/confirm, invalid replay error; Home, Rules and Setup goldens updated.

## Exact validation

- Glass buildq #4875: `flutter test test/visual_test.dart --update-goldens` — PASS.
- Glass buildq #4877: `flutter build apk --release` — PASS, 54.8 MB; installed only on isolated Glass Waydroid user 11.
- Glass buildq #4882: `flutter test test/ --reporter expanded` — PASS, **123 tests**.
- Glass buildq #4883: `flutter analyze lib test tool` — PASS, **No issues found**.
- Glass buildq #4884: isolated scaffold `flutter build linux --release` — PASS (original repo lacks its own Linux scaffold).
- `git diff --check` — PASS before commit.

## Actual UI and visual findings

- **Waydroid, Glass, user 11, 432×960:** audited Home, Rules, advanced rules, glossary, Match setup local modes/seat counts/human names/world seed, AI match launch, Board, resume saved match, overwrite Cancel, back navigation, LAN create/join setup, replay import and invalid-code error. Screen-specific screenshot rows document taps, swipes, keyboard entry and expected/actual. Clean bottom navigation, legible hierarchy, no observed overflow. Re-captured polished setup and replay error after fixes.
- **Linux, Glass, headless Cage:** final Home visually inspected after release build; keyboard Tab traverses New local match, Rules and LAN, and Return actually opens LAN setup. Screenshot rows 48–53 preserve each step. Keyboard focus highlight on the main CTA remains subtle.
- Early Android launch failed while isolated user 11 was still initializing; second launch succeeded. First malformed-code snackbar echoed parser data; fixed and re-tested. A tap intended to collapse a setup subsection missed its moving target and was marked as a failed action, not proof of a software defect.

## Gaps and boundaries

- No live multi-device LAN handshake, actual room creation/join, replay acceptance with a valid shared code, complete AI match to victory, or every board-action edge was proven in this Home/setup slice. No Nox execution was required. Offline-first screen flow was tested, but formal accessibility audit and high-density responsive landscape sweeps remain.
- Initial Linux keyboard probe was ambiguous; final attempt demonstrated Tab highlight and Enter LAN navigation. Browser/service APIs were not involved.
- One concurrently modified `lib/ui/match_screen.dart` and unrelated `.serena/`, `test/failures/`, `tool/` files were preserved and intentionally excluded from the Slice 11 commit.

## Final handoff and environment restoration

- Commit on `main`: `126b99a` (`Polish offline Home rules and match setup`); 12 scoped files. Not pushed.
- Glass Waydroid current Android user restored to **0**; display size restored to **1792×1008**; isolated Linux Cage service `sb-ai11-linux-final` stopped. QA user 11 remains isolated for reproducibility; no Samsung touched.
- Preserved unrelated uncommitted state: `lib/ui/match_screen.dart`, `.serena/`, `test/failures/`. No files belonging to other sessions were reset or staged.
