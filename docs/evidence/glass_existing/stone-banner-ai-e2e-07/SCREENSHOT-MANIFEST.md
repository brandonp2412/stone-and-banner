# Slice 07 — screenshot and action manifest

4 November 2026 NZDT · Glass Linux isolated headless Wayland (`cage`) and Glass Waydroid release app.

All **28 saved PNGs** were visually reviewed (the four intermediate Linux Tab frames together in a 2×2 inspection sheet). The two black initial-frame captures are **failed visual states** and were recaptured after rendering. None of the screenshots establish a full human-versus-AI match; Waydroid was concurrently controlled by another session.

| # | Screen/action | Expected | Actual observed | Saved screenshot | Visual verdict |
| --- | --- | --- | --- | --- | --- |
| 1 | Waydroid launch | Home ready (landscape) | Home, saved-match entry, Hot-seat setup rendered | [PNG](waydroid-01-launch-20261104-1954.png) | PASS — centered hierarchy, readable though narrow on large landscape |
| 2 | Waydroid orientation request | Portrait orientation | Orientation API reported success; display stayed 1792×1008; Vs AI selection changed externally | [PNG](waydroid-02-portrait-20261104-1956.png) | LIMITED — screen readable, rotation not proven; shared-device interference |
| 3 | Waydroid resize to 432×960 | Portrait Home setup | Portrait Home, Vs AI, 3 players, 1 AI, Start visible above bottom bar | [PNG](waydroid-03-portrait-size-20261104-1957.png) | PASS — contrast, spacing, hierarchy and touch targets readable; lower actions scroll |
| 4 | Waydroid choose 4 players | 4-player controls and 3 AI choice | 4 players selected; 3 AI offered, but AI count also changed to 2 without attributable action | [PNG](waydroid-04-select-four-players-20261104-1958.png) | PASS layout; LIMITED attribution due concurrent control |
| 5 | Waydroid tap stale AI target | 3 AI chosen | Target ref invalid; unexpected Player 1 setup board appeared after another session started match | [PNG](waydroid-05-three-ai-20261104-1959.png) | NOT VERIFIED — visually reviewed board; no 3-AI tap or keyboard claim |
| 6 | Linux first headless launch | App first frame | Black frame before GTK/Flutter rendered | [PNG](linux-01-headless-launch-20261104-2004.png) | FAIL first frame; recaptured after compositor/app settled |
| 7 | Linux headless service launch | App first frame | Black first frame on new isolated service | [PNG](linux-03-headless-service-20261104-2006.png) | FAIL first frame; recaptured at linux-04 |
| 8 | Linux rendered Home | Hot-seat setup visible | Home with large centered setup, Hot-seat, Start and LAN entry | [PNG](linux-04-headless-later-20261104-2006.png) | PASS — consistent fonts, contrast, alignment; no overflow |
| 9 | Linux Tab 1 | Focus traversal | No selected value changed on immediate capture | [PNG](linux-05-keyboard-tab-20261104-2008.png) | PASS layout; focus state not visually resolved |
| 10 | Linux Tab 2 | Focus traversal | Home selections unchanged | [PNG](linux-06-keyboard-tab-20261104-2009.png) | PASS layout; focus state not visually resolved |
| 11 | Linux Tab 3 | Focus traversal | Home selections unchanged | [PNG](linux-07-keyboard-tab-20261104-2009.png) | PASS layout; focus state subtle |
| 12 | Linux Return | Activate focused control | Immediate frame still Hot-seat; later transition reflects asynchronous input | [PNG](linux-08-keyboard-return-20261104-2009.png) | PASS layout; action outcome not attributable to this frame alone |
| 13 | Linux Tab | Keyboard mode navigation | Vs AI now visibly selected; 1/2 AI controls exposed | [PNG](linux-09-keyboard-tab-20261104-2010.png) | PASS — mode transition, compact hierarchy and selection clearly visible |
| 14 | Linux Return | Keyboard activation | Vs AI remains selected; 1 AI checked | [PNG](linux-10-keyboard-return-20261104-2010.png) | PASS layout; no additional selection change |
| 15 | Linux Tab | Focus traversal | Vs AI, 3 players, 1 AI remain selected | [PNG](linux-11-keyboard-tab-20261104-2012.png) | PASS — no clipping; focus highlight not obvious |
| 16 | Linux Tab | Focus traversal | Selection unchanged | [PNG](linux-12-keyboard-tab-20261104-2012.png) | PASS — no clipping; focus highlight not obvious |
| 17 | Linux Tab | Focus traversal | Selection unchanged | [PNG](linux-13-keyboard-tab-20261104-2012.png) | PASS — no clipping; focus highlight not obvious |
| 18 | Linux Tab | Focus traversal | Selection unchanged | [PNG](linux-14-keyboard-tab-20261104-2012.png) | PASS — no clipping; focus highlight not obvious |
| 19 | Linux Return | Activate focused control | Home still shows Vs AI, 1 AI immediately | [PNG](linux-15-keyboard-return-20261104-2012.png) | PASS layout; no independent selection change established |
| 20 | Linux Right | Keyboard navigation | Navigated to Player 1 private handoff screen (start had processed asynchronously) | [PNG](linux-16-keyboard-right-20261104-2013.png) | PASS — centered sparse action card, private state hidden; key attribution uncertain |
| 21 | Linux Return | Activate focused control | Player 1 privacy handoff remains with I'm ready action | [PNG](linux-17-keyboard-return-20261104-2013.png) | PASS — readable, clear next action and no content leak |

| 22 | Waydroid choose Vs AI from Home | AI setup shown | Vs AI selected; 1/2 AI and Start new match rendered; saved-match button wraps at 432×960 | [PNG](waydroid-06-vs-ai-20261104-2018.png) | FAIL — wrapped destructive-action label, corrected later in source |
| 23 | Waydroid choose 4 players | 3-AI choice exposed | 4 players selected; 1 AI remained selected, 3 AI visible | [PNG](waydroid-07-four-players-20261104-2019.png) | PASS — selection and three-option spacing correct; button still wraps |
| 24 | Waydroid attempt 3-AI target (wrong ref) | 3 AI selected | Tap landed on non-AI view; 1 AI remained selected | [PNG](waydroid-08-select-three-ai-20261104-2019.png) | NOT VERIFIED — no selection change; saved for truthful action accounting |
| 25 | Waydroid attempt 3 AI (concurrent nav) | 3 AI selected | Tap returned success, but another session navigated to LAN page before screenshot | [PNG](waydroid-09-select-three-ai-20261104-2020.png) | LIMITED — LAN screen visually clean; 3-AI action outcome not independently attributable |
| 26 | Waydroid restore default display size | 1792×1008 original geometry | Restored physical size; later Home showed 4 players and 3 AI selected | [PNG](waydroid-10-display-restored-20261104-2022.png) | PASS — no layout clipping; 3-AI visibly selected but match not started |
| 27 | Linux relaunched corrected release | New Home frame | Black startup frame before paint | [PNG](linux-18-after-saved-button-fix-20261104-2023.png) | FAIL transient frame; recaptured at linux-19 |
| 28 | Linux saved-match copy correction | One-line Start and explicit save warning | Stable Home displayed Start new match on one line with smaller Replaces your saved match caption | [PNG](linux-19-after-saved-button-fix-20261104-2023.png) | PASS — typography, alignment, density and action clarity corrected |

## Limits and interaction accounting

- **Waydroid:** actual installed release APK; Home setup, selected 4-player mode and exposed 3-AI option observed at 432×960; later 3 AI was visibly selected, but concurrent navigation prevents reliably attributing that particular tap; name-keyboard entry remains **not** verified.
- **Linux:** actual release executable in an isolated temporary Linux desktop scaffold, hosted by headless Wayland/cage; Home, Vs AI selection, and a private handoff were observed by screenshot. Key sends returned success; frame latency means not every individual key can be mapped unambiguously to the later transition. No Linux text-entry claim.
- **Visual review:** text hierarchy, touch-target width, dark palette contrast, start-action visibility, spacing, density and content privacy looked acceptable in stable Home/handoff frames. Focus indicators were subtle in some Tab frames. The initial black frames were transient rendering readiness failures, not acceptable UI captures.
- All screens/actions we attempted are listed above, including failed/ambiguous interactions. No Samsung or public deployment. No observed full match completion or human-AI victory claim.

- A portrait screenshot exposed a wrapped saved-match button label. After the minimal single-line label + explicit caption correction, the isolated Linux release was rebuilt and screenshot 28 visually confirmed the fix; the corrected APK built but was not reinstalled on the shared Waydroid.
