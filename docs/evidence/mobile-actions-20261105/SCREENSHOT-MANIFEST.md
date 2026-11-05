# Completion 1/8 — Mobile gameplay UI screenshot manifest (5 Nov 2026 NZDT)

## Provenance and acceptance boundary

- **Actual Android device:** Nox Waydroid x86_64, ADB `192.168.240.2:5555`, user 11, Android 13, override **390 × 844 px**. Captured with `adb exec-out screencap -p` after the indicated real tap or launch. The existing game app and saved data were never uninstalled.
- **Glass Waydroid was shared/occupied** (Instagram, then SloppaTV), so it was not seized. These are **Nox Waydroid** images, not Glass Waydroid or Samsung proof. A separate headless Glass Linux release was opened at 390 × 844, but only Home/keyboard exploration was screen-captured; the human-action screen was not reached there.
- **Before:** the pre-existing signed game installation in Nox Waydroid, already on Round 1/actions, scrolled to the lower controls; exact binary source revision unverified.
- **After:** isolated QA package `nz.presley.stoneandbanner.mobileuiqa`, built from source revision `353c8aa` with only temporary package-ID/app-label differences; SHA-256 `5f5ce05dfda7500d0e4ee5dd117d197cefadbe8d871a9909fc4d0db51ad78617` (buildq `#5008`). The original package remains installed.
- **Comparison:** [before vs after](comparison-before-after.png), left before / right after, both 390 × 844. These are different saved matches and scroll positions, so this is a UI comparison, **not pixel-identical state replay**.

| Image | Real action / observed outcome | Visual review |
| --- | --- | --- |
| [Before](before-nox-waydroid-390x844.png) | Old signed app, Round 1/actions, lower panel | **FAIL (density):** disabled Develop controls, tightly packed trade/End Turn buttons with text wrapped to two lines; legal next action not visible above board |
| [QA Home](qa-home.png) | Launch separate QA APK | **PASS:** readable Home, dark contrast, large New Match |
| [Setup](qa-setup.png) | Tap New local match | **PASS:** setup choices visible, no clipping |
| [Vs AI](qa-ai-setup.png) | Select Vs AI | **PASS:** computer-count options visible |
| [Two AI](qa-two-ai.png) | Select 1 human + 2 AI | **PASS:** explicit seat composition |
| [First Village](qa-start.png) | Start match | **PASS:** board and target selector visible at 390 × 844 |
| [Village targets](qa-first-targets.png) | Open legal-target sheet | **PASS:** numbered locations readable; list scrollable |
| [Village placed](qa-first-village.png) | Choose Junction 1 | **PASS:** updates to setupRoad |
| [Road targets](qa-road-targets.png) | Open legal-road sheet | **PASS:** legal target descriptions readable |
| [AI draft](qa-after-first-road.png) | Choose first Road; AI performs draft, returns human | **PASS:** pieces visible, human resumes setupVillage |
| [Second village targets](qa-second-village-targets.png) | Open second junction sheet | **PASS:** layout readable |
| [Second Village](qa-second-village.png) | Choose second legal junction | **PASS:** 2 VP and setupRoad |
| [Second Road targets](qa-second-road-targets.png) | Open legal-road sheet | **PASS:** options readable |
| [Ready to roll](qa-ready-roll.png) | Choose second Road | **PASS:** large Roll Dice is now **above** the board |
| [Initial revised panel](qa-action-panel-after.png) | Roll Dice into actions (before compact adjustment) | **LIMITED:** legal-unavailable buttons removed, but icon trade buttons wrapped into two rows and panel remained too tall |
| [Rebuilt QA Home](qa-compact-first.png) | Install updated side-by-side QA package; launch | **PASS:** saved match retained, Continue visible |
| [Final revised panel](qa-compact-after.png) | Continue saved match, Round 1/actions | **PASS:** clear next action, explanatory no-build state, full-width End Turn, Bank/Player Trade alongside; board remains available below |

All listed PNGs were opened and visually inspected for contrast, typography, controls, clipping, next-action hierarchy and interaction result. No screenshot was accepted solely because a golden or widget test passed.

### Residual UI boundaries

- The board begins below the action card at 390 × 844; users still scroll for full board inspection. Legal board targets also have the large accessible list button, proven during setup, but building with resources in the *new* action panel was not tapped on Android; only widget-tested.
- Live strategy card play, bank/trade completion, Knight and Invasion responses were not exercised through this Android build. Existing engine and focused tests remain separate evidence.
- Glass Waydroid and physical Samsung acceptance remain **unverified**. The original Nox package rejected a replacement APK due to mismatched signatures, so the side-by-side QA package was used without uninstalling or overwriting saved data.
