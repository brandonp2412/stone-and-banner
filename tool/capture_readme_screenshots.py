#!/usr/bin/env python3
"""Capture real web gameplay for the README using an isolated browser profile.

Run: uv run --with patchright==1.64.4 python tool/capture_readme_screenshots.py
Requires a Patchright Chromium browser (patchright install chromium).
The script never accesses the player's browser profile or saved matches.
"""

import argparse
import asyncio
import os
import re
import time
from pathlib import Path

from patchright.async_api import async_playwright


async def dismiss_hints(page):
    for _ in range(5):
        got_it = page.get_by_text("Got it", exact=True).first
        if await got_it.count() and await got_it.is_visible():
            await got_it.click()
            await page.wait_for_timeout(200)
        else:
            break


async def wait_for_control(page, label, timeout_seconds=100):
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        await dismiss_hints(page)
        control = page.get_by_text(label, exact=True).first
        if await control.count() and await control.is_visible():
            return control
        await page.wait_for_timeout(650)
    raise TimeoutError(f"Never reached '{label}'. Visible text: {(await page.locator('body').inner_text())[:1100]}")


def junction_score(label):
    values = [int(x) for x in re.findall(r"\b(2|3|4|5|6|8|9|10|11|12)\b", label.split(":", 1)[1])]
    return sum(6 - abs(7 - n) for n in values)


async def pick_legal_target(page, control_label, prefix):
    control = await wait_for_control(page, control_label)
    await control.click()
    await page.get_by_text("Choose legal board target", exact=True).wait_for(timeout=10000)
    entries = await page.locator("body").inner_text()
    candidates = [line for line in entries.splitlines() if re.match(rf"^{prefix} \d+: ", line)]
    if not candidates:
        raise RuntimeError(f"No legal {prefix.lower()} shown: {entries[:1500]}")
    if prefix == "Junction":
        choice = max(candidates, key=junction_score)
    else:
        choice = candidates[0]
    target_number = re.search(rf"^{prefix} (\d+):", choice).group(1)
    await page.get_by_text(re.compile(rf"^{prefix} {target_number}:"), exact=False).first.click()
    await page.wait_for_timeout(350)
    print(f"Selected {choice}", flush=True)


async def screenshot(page, destination):
    await page.wait_for_timeout(600)
    await page.screenshot(path=str(destination), animations="disabled", full_page=False)
    import struct
    data = destination.read_bytes()
    assert data.startswith(b"\x89PNG\r\n\x1a\n"), destination
    width, height = struct.unpack(">II", data[16:24])
    assert width > 300 and height > 300, destination
    print(f"Captured {destination}", flush=True)


async def main(args):
    args.output.mkdir(parents=True, exist_ok=True)
    async with async_playwright() as p:
        launch = {"headless": True, "args": ["--no-sandbox", "--disable-dev-shm-usage"]}
        if args.chromium:
            launch["executable_path"] = args.chromium
        browser = await p.chromium.launch(**launch)
        context = await browser.new_context(viewport={"width": 1440, "height": 900}, device_scale_factor=1, reduced_motion="reduce")
        page = await context.new_page()
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        await page.goto(args.url, wait_until="domcontentloaded", timeout=45000)
        await page.locator("flt-semantics-placeholder").evaluate("el => el.click()", timeout=20000)
        await page.get_by_text("New local match", exact=True).wait_for(timeout=30000)
        await screenshot(page, args.output / "home-desktop.png")
        await page.get_by_text("New local match", exact=True).click()
        await page.get_by_text("Match setup", exact=True).wait_for(timeout=20000)
        # Flutter's game-option chips are painted but not exposed as text semantics.
        # This fixed point is inside the Vs AI chip in the 1440x900 setup layout.
        await page.mouse.click(340, 292)
        await page.get_by_text("1 human · 2 computers", exact=True).wait_for(timeout=10000)
        await page.get_by_text("Start match", exact=True).click()
        await page.get_by_text("Realm Realm", exact=True).wait_for(timeout=30000)
        # Set up a genuine three-seat match. The AI chooses its own moves; all
        # settlements and roads for the human are legal actions through the UI.
        for round_number in range(2):
            await pick_legal_target(page, "Choose site", "Junction")
            await pick_legal_target(page, "Choose road", "Road")
            print(f"Completed starting placement {round_number + 1}", flush=True)
        await dismiss_hints(page)
        await page.wait_for_timeout(1100)
        await screenshot(page, args.output / "match-desktop.png")
        await page.set_viewport_size({"width": 430, "height": 932})
        await page.wait_for_timeout(700)
        await screenshot(page, args.output / "match-mobile.png")
        await page.set_viewport_size({"width": 915, "height": 412})
        await page.wait_for_timeout(700)
        await screenshot(page, args.output / "match-landscape.png")
        if errors:
            print("Page errors:", errors, flush=True)
        await context.close()
        await browser.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="https://brandonp2412.github.io/stone-and-banner/")
    parser.add_argument("--output", type=Path, default=Path("docs/screenshots"))
    parser.add_argument("--chromium", default=os.environ.get("CHROMIUM_EXECUTABLE"))
    asyncio.run(main(parser.parse_args()))
