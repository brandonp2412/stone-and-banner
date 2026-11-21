# Slice 20/20 — final independent release QA handoff

Host: Nox fallback, 5 November 2026 NZDT. Glass execution connector returned HTTP 429; no Glass code was accessed. Source HEAD at start: `384f549e0a75004705a867e1ecaf3ccd36ef8084`. No Samsung or public deployment.

## Fresh automated verification

- `buildq #4568` Flutter analyze lib test tool: PASS, no issues.
- `buildq #4569` full Flutter suite: PASS, **137 tests**. The suite does not prove exhaustive UI or human-game coverage.
- `buildq #4570` Android release: PASS, APK **54890298 bytes**, SHA-256 `5be32b0728998fee6bfc2b23f507a81cda992363c547d8c39ac5036ef1a61958`. Built, **not installed**.
- `buildq #4574` Linux release: PASS. Actual GUI run on Nox isolated Xvfb; first session uses prior built binary, second fixture session uses freshly rebuilt release.
- `buildq #4575` LAN smoke: PASS, 3 sockets, room creation, authority, dedupe, filtered fan-out and reconnect to revision 1. This is protocol proof, **not** separate GUI LAN E2E.
- `buildq #4577` regenerated deterministic stage8 scenario fixtures: PASS, pre-win at seed 1000, 1,143 events, Town Junction 42 -> Capital, predicted winner seat 0.

## Live Linux trace

See [40-row per-action screenshot and visual review manifest](SCREENSHOT-MANIFEST.md); PNGs alongside. In a fresh 390×844 isolated Xvfb profile: Home -> Vs AI -> 3 seats -> 2 AI -> Start -> human Village at Junction 1 -> Road 1 -> computer setup -> human second Village Junction 3 -> Road 3 -> Roll dice -> scroll -> End Turn -> visible computer-turn progress -> Round 2 human -> Home -> Continue saved match. Human had 2 VP; computer seats had 2 VP each and a computer Road count increased. Saved prefs had both local session and replay keys. No continuous 15-VP AI victory claimed.

Independent second Linux profile: Home -> Import replay -> slow-type fresh sbz1 pre-win fixture -> Load -> Bot-0 privacy handoff -> Round 90, 12 VP -> Upgrade -> legal Junction 42 -> winner 15/15 VP (event 1144). Winner frame showed `Bot-0 wins!`, 15 VP, and Capital ownership. Fast keyboard injection first caused a rejected code; preserved evidence, corrected by 3ms key delay. This is **real release UI** on a seeded fixture, not a live AI game from initial setup.

## Exact release acceptance matrix

| Gate | Linux | Waydroid |
| --- | --- | --- |
| Start, choose human and two offline AI, legal draft | PASS real GUI | NOT RUN |
| Real dice + AI turn cycle + save/resume | PASS real GUI through Round 2 | NOT RUN |
| Human-vs-AI natural match to 15 VP | NOT PROVEN | NOT RUN |
| Seeded 15-VP victory continuation | PASS real GUI (fixture, not natural match) | NOT RUN |
| LAN 3-socket protocol authority/filter/reconnect | PASS automated protocol, GUI not tested | NOT RUN |
| Independent LAN host/guest GUI, disconnect/reconnect | NOT RUN this slice; see Slice 16 prior evidence | NOT RUN |
| All cards, trades, tactical reactions in actual UI | NOT RUN this slice; reducer/widget suites pass, see prior Slices 15/16 | NOT RUN |
| Rematch UI after win | NO DIRECT CTA OBSERVED; unproven | NOT RUN |
| Release APK build | PASS | NOT INSTALLED/LAUNCHED |
| Accessibility / production security / signing / legal | OPEN | OPEN |

## Blockers and unresolved defects

1. Glass HTTP 429 blocked requested first-choice host. Nox Waydroid user 11 was foreground with another Stone & Banner client; switching or installing the shared Android package risked disturbing ongoing work, so no isolated Waydroid install or UI claim.
2. Natural 15-VP match in Vs AI mode, two-GUI LAN session, UI cards/trades/reactions, adverse network reconnect, rematch and phone visual matrix remain acceptance **FAIL/UNPROVEN**, not complete.
3. Linux GTK starts at 1280×720 even on 390×844 Xvfb, requiring resize. First captured blank frame/transitional sheets were preserved and corrected.
4. Winner frame lacks a direct Rematch CTA in observed viewport. Full-scale accessibility, signing, host crash room persistence, cleartext LAN security and legal/IP gates remain open from Stage 8 and Slice 16.

Source changes in other simultaneous slices were preserved, not staged. Only factual Slice 20 audit documentation is eligible for commit; no gameplay code change was attempted in this final QA window.

Cleanup: stopped only the four `stone20-*` isolated GUI/Xvfb test services; retained screenshot PNGs, manifests, isolated test data and release binaries. No existing Waydroid user or unrelated service changed.
