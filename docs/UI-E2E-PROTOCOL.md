# Cross-platform live screenshot QA protocol (Slice 10/20)

Run from **Glass first**, or from **Nox** when explicitly available; never use
Samsung or a production/public deployment. Harness source:
[tool/e2e_screenshot_harness.py](../tool/e2e_screenshot_harness.py).
The Python 3 standard-library harness is reusable on either host. It captures
a PNG after **every screen opening and every meaningful action**. Its
append-only JSONL log preserves failed or ambiguous actions; visual review is
a separate required step. Saving a screenshot alone never confers PASS.

## Host/mode matrix

| Host | Linux | Android |
| --- | --- | --- |
| Glass | Isolated hidden/headless cage compositor, wtype keys, grim PNG | Glass **Waydroid x86_64 only**, adb taps/keys/swipes, screencap |
| Nox | Same compositor/keyboard/capture protocol if binaries present | Nox **Waydroid only**, same adb commands |

On Linux, set WLR_BACKENDS=headless and WLR_HEADLESS_OUTPUTS=1 for cage and
record the **new** WAYLAND_DISPLAY socket. Use isolated XDG_CONFIG_HOME
to keep saved matches separate. A Linux host can be generated in a temporary
source snapshot with flutter create --platforms linux when the checked-out
repo lacks one. Do not add generated Linux code to this Android-targeted
checkout. Compile using buildq and record the executable SHA-256. Never
inject keyboard events into a visible compositor.

On Waydroid, select an exact --adb-serial observed using adb devices -l.
The harness reads ro.product.model and **refuses any model not containing
Waydroid**. Treat shared-device navigation by another session as contaminated,
capture the actual result and report LIMITED/FAIL.

## Minimal command sequence

Use one root per platform/session; these illustrative values must be replaced
with the precise metadata and display/serial observed on the host.

~~~bash
python3 tool/e2e_screenshot_harness.py init \
  --root /home/brandon/.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-10/linux-glass \
  --session slice10-linux-glass --host glass --platform linux \
  --app-version 0.8.0+8 --build-id sha256:ACTUAL_HASH \
  --source-revision ACTUAL_SHA --wayland-display wayland-3

# Immediately after launching the actual app in the isolated compositor:
python3 tool/e2e_screenshot_harness.py capture \
  --root /home/brandon/.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-10/linux-glass \
  --flow hotseat-start --kind screen-open --action "Open Home" \
  --expected "Home visible with setup controls"

# One action and its immediate screenshot are inseparable:
python3 tool/e2e_screenshot_harness.py act \
  --root /home/brandon/.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-10/linux-glass \
  --flow hotseat-start --kind action --action "Focus next control" \
  --expected "Focus moves" --input key --key Tab

# Inspect actual PNG, then record evidence-based verdict:
python3 tool/e2e_screenshot_harness.py review \
  --root /home/brandon/.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-10/linux-glass \
  --id 1 --actual "Home rendered" --verdict PASS --severity none \
  --critique "Good contrast, alignment, breathing room and primary CTA"

python3 tool/e2e_screenshot_harness.py complete --root ROOT \
  --flow hotseat-start --status PASS --notes "Observed entire flow"
python3 tool/e2e_screenshot_harness.py report --root ROOT
python3 tool/e2e_screenshot_harness.py verify --root ROOT --require-flows 1
~~~

Android substitutes --platform waydroid --adb-serial DEVICE at init,
uses act --input launch for the exported MainActivity and
act --input tap --x 220 --y 540, --input key --key KEYCODE_BACK, or
--input swipe --x X --y Y --end-x X --end-y Y --duration-ms 300.

## Manifest schema and review rubric

- Session (session.json): exact host, Linux/Waydroid platform, app version,
  source revision, build SHA, display or Android serial, start time.
- Append-only manifest.jsonl: capture ID, flow, screen-open/action kind,
  timestamp UTC and NZDT, semantic action and keyboard/coordinate command,
  expected result, actual (initially UNREVIEWED), PNG name/dimensions and
  settle milliseconds; subsequent review event supplies actual/verdict,
  visual critique, defect severity and optional retest ID.
- Collision-resistant PNG filenames contain UTC timestamp/nanoseconds,
  host, platform, row, action slug and UUID; exclusive create prevents
  overwrites. Verify checks unique names, PNG chunk CRCs and dimensions, ordered captures,
  visual-review completeness and number of completed PASS flows.
- Visually inspect **each actual PNG** for typography, contrast, hierarchy,
  whitespace, density, alignment, focus/pressed states, clipping/overflow
  and clear next actions. Explicitly document visual defects even when the
  functional result succeeds.
- Severity: none, minor (cosmetic), major (obscured interaction), critical
  (unusable/privacy leak). Verdict: PASS, LIMITED (state or attribution
  uncertain), FAIL. Fix defects and recapture; link follow-up with
  --retest-id. Never erase failed/black/ambiguous frames.
- A complete flow needs observed start/end states, action captures and
  reviewed images. The complete command refuses fewer than two captures or
  pending visual reviews. Failed predecessor stages do not block this QA.

Run python3 -m unittest tool/test_e2e_screenshot_harness.py -v for unit
tests of metadata, naming, review gates, host-scoped keyboard input and
physical-device refusal; a live app flow is still required for E2E claims.
