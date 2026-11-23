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
import json
import subprocess
from urllib.parse import urlparse, unquote
from pathlib import Path

from patchright.async_api import async_playwright


async def dismiss_hints(page):
    for _ in range(5):
        got_it = page.get_by_text("Got it", exact=True).first
        if await got_it.count() and await got_it.is_visible():
            await got_it.click(force=True)
            await page.wait_for_timeout(200)
        else:
            break


def fresh_replay():
    root = Path(__file__).resolve().parent.parent
    config_path = root / ".dart_tool/package_config.json"
    config = json.loads(config_path.read_text())
    sdk = Path(unquote(urlparse(config["flutterRoot"]).path))
    dart = sdk / "bin/cache/dart-sdk/bin" / ("dart.exe" if os.name == "nt" else "dart")
    result = subprocess.run(
        [str(dart), f"--packages={config_path}", str(root / "tool/make_screenshot_replay.dart")],
        check=True, capture_output=True, text=True, timeout=120, cwd=root,
    )
    replay = result.stdout.strip()
    json.loads(replay)
    return replay


async def screenshot(page, destination):
    await page.wait_for_timeout(600)
    visible = await page.locator("body").inner_text()
    labels = await page.locator("[aria-label]").evaluate_all(
        "nodes => nodes.map(node => node.getAttribute('aria-label')).join('\\n')"
    )
    visible += "\n" + labels
    forbidden = re.search(
        r"\b(?:catan|settlements?|knights?|barbarians?|robber|aqueduct|metropolis)\b|longest road|victory points?|progress cards?",
        visible, re.IGNORECASE,
    )
    if forbidden:
        raise AssertionError(f"Old terminology in {destination}: {forbidden.group()}")
    await page.screenshot(path=str(destination), animations="disabled", full_page=False)
    import struct
    data = destination.read_bytes()
    assert data.startswith(b"\x89PNG\r\n\x1a\n"), destination
    width, height = struct.unpack(">II", data[16:24])
    assert width > 300 and height > 300, destination
    print(f"Captured {destination}", flush=True)


async def main(args):
    args.output.mkdir(parents=True, exist_ok=True)
    replay = args.replay.read_text() if args.replay else fresh_replay()
    async with async_playwright() as p:
        launch = {"headless": True, "args": ["--no-sandbox", "--disable-dev-shm-usage"]}
        if args.chromium:
            launch["executable_path"] = args.chromium
        browser = await p.chromium.launch(**launch)
        context = await browser.new_context(viewport={"width": 1440, "height": 900}, device_scale_factor=1, reduced_motion="reduce")
        await context.add_init_script("localStorage.setItem('flutter.gameplay_hints_enabled', 'false')")
        page = await context.new_page()
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        await page.goto(args.url, wait_until="domcontentloaded", timeout=45000)
        await page.locator("flt-semantics-placeholder").evaluate("el => el.click()", timeout=20000)
        await page.get_by_text("New local match", exact=True).wait_for(timeout=30000)
        await screenshot(page, args.output / "home-desktop.png")
        await page.get_by_text("Learn the rules", exact=True).click()
        await page.get_by_text("The founding rules", exact=True).wait_for()
        await screenshot(page, args.output / "rules-desktop.png")
        await page.reload(wait_until="domcontentloaded")
        await page.locator("flt-semantics-placeholder").evaluate("el => el.click()")
        await page.get_by_text("New local match", exact=True).wait_for()
        await page.get_by_text("New local match", exact=True).click()
        await page.get_by_text("Match setup", exact=True).wait_for()
        await screenshot(page, args.output / "setup-desktop.png")
        # Seed only this newly created browser context. Restoration uses the
        # production saved-session format; the player's browser is untouched.
        session = json.dumps({"version": 2, "replay": replay, "computerSeats": []})
        await page.evaluate("""session => {
            localStorage.setItem('flutter.stone_banner_local_session_v2', JSON.stringify(session));
        }""", session)
        await page.reload(wait_until="domcontentloaded")
        await page.locator("flt-semantics-placeholder").evaluate("el => el.click()")
        await page.get_by_text("Continue saved match", exact=True).click()
        await page.get_by_text("I'm ready", exact=True).click()
        await page.wait_for_timeout(1100)
        await dismiss_hints(page)
        await screenshot(page, args.output / "match-desktop.png")
        # These canvas-painted tabs have no text node in web semantics.
        # Coordinates are inside their centres at the fixed desktop viewport.
        await page.mouse.click(1395, 80)
        await screenshot(page, args.output / "realm-desktop.png")
        await page.mouse.click(1125, 80)
        await page.set_viewport_size({"width": 430, "height": 932})
        await page.wait_for_timeout(700)
        await screenshot(page, args.output / "match-mobile.png")
        await page.set_viewport_size({"width": 915, "height": 412})
        await page.wait_for_timeout(700)
        await screenshot(page, args.output / "match-landscape.png")
        if errors:
            raise RuntimeError(f"Page errors: {errors}")
        await context.close()
        await browser.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="https://brandonp2412.github.io/stone-and-banner/")
    parser.add_argument("--output", type=Path, default=Path("docs/screenshots"))
    parser.add_argument("--replay", type=Path, help="Capture this replay instead of generating an independent match")
    parser.add_argument("--chromium", default=os.environ.get("CHROMIUM_EXECUTABLE"))
    asyncio.run(main(parser.parse_args()))
