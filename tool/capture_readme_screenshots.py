#!/usr/bin/env python3
"""Capture real web gameplay for the README and Fastlane in isolated browser profiles.

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


async def screenshot(page, destination, expected_size):
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
    assert (width, height) == expected_size, (destination, width, height)
    assert data[24:26] == bytes([8, 2]), f"Expected 24-bit RGB PNG: {destination}"
    assert len(data) <= 8 * 1024 * 1024, f"Screenshot exceeds 8 MB: {destination}"
    print(f"Captured {destination}", flush=True)


# CSS viewport dimensions exercise the actual responsive layouts; device scale
# factors yield the store image sizes without stretching or post-processing.
PROFILES = (
    ("phoneScreenshots", 432, 768, 2.5),
    ("sevenInchScreenshots", 960, 540, 2),
    ("tenInchScreenshots", 1280, 720, 2),
)


async def enable_semantics(page):
    await page.locator("flt-semantics-placeholder").evaluate(
        "el => el.click()", timeout=30000
    )


async def click_text(page, label):
    # Flutter controls can appear as text nodes or accessible labels.
    target = page.get_by_text(label, exact=True).or_(
        page.get_by_label(label, exact=True)
    ).first
    await target.click(timeout=15000)
    await page.mouse.move(0, 0)


async def capture_profile(browser, args, replay, profile):
    category, width, height, scale = profile
    destination = args.output / category
    destination.mkdir(parents=True, exist_ok=True)
    expected = (round(width * scale), round(height * scale))
    context = await browser.new_context(
        viewport={"width": width, "height": height},
        device_scale_factor=scale,
        reduced_motion="reduce",
    )
    await context.add_init_script(
        "localStorage.setItem('flutter.gameplay_hints_enabled', 'false')"
    )
    page = await context.new_page()
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))
    try:
        await page.goto(args.url, wait_until="domcontentloaded", timeout=45000)
        await enable_semantics(page)
        await page.get_by_text("New local match", exact=True).wait_for(timeout=30000)
        await click_text(page, "New local match")
        await page.get_by_text("Match setup", exact=True).wait_for()
        await screenshot(page, destination / "04-setup.png", expected)
        session = json.dumps({"version": 2, "replay": replay, "computerSeats": []})
        await page.evaluate("""session => {
            localStorage.setItem('flutter.stone_banner_local_session_v2', JSON.stringify(session));
        }""", session)
        await page.reload(wait_until="domcontentloaded")
        await enable_semantics(page)
        await click_text(page, "Continue saved match")
        await click_text(page, "I'm ready")
        await page.wait_for_timeout(1100)
        await dismiss_hints(page)
        await screenshot(page, destination / "01-board.png", expected)
        if width < 900:
            await click_text(page, "Actions")
        # Canvas tabs currently have no web accessibility nodes. Match the
        # responsive tab row geometry and verify the resulting panel content.
        async def select_tab(index):
            left = 40 if width < 900 else width - 320
            y = 25 if width < 900 else 79
            await page.mouse.click(left + (width - left) * (index + 0.5) / 4, y)
            await page.mouse.move(0, height - 1)

        await select_tab(3)
        await page.wait_for_timeout(600)
        assert "Your realm" in await page.locator("body").inner_text(), "Realm tab did not open"
        await screenshot(page, destination / "03-realm.png", expected)
        await select_tab(1)
        await page.get_by_text("Player trade", exact=True).wait_for(timeout=10000)
        await click_text(page, "Player trade")
        await page.wait_for_timeout(600)
        assert "Send offer" in await page.locator("body").inner_text(), await page.locator("body").inner_text()
        await screenshot(page, destination / "02-trade.png", expected)
        if errors:
            raise RuntimeError(f"Page errors in {category}: {errors}")
    finally:
        await context.close()


async def main(args):
    import tempfile
    replay = args.replay.read_text() if args.replay else fresh_replay()
    # Stage the whole set before replacing tracked screenshots, so failed
    # captures cannot leave a partial listing.
    output = args.output
    with tempfile.TemporaryDirectory(prefix="stone-screens-") as temp:
        args.output = Path(temp)
        async with async_playwright() as p:
            launch = {"headless": True, "args": ["--no-sandbox", "--disable-dev-shm-usage"]}
            if args.chromium:
                launch["executable_path"] = args.chromium
            browser = await p.chromium.launch(**launch)
            try:
                for profile in PROFILES:
                    await capture_profile(browser, args, replay, profile)
            finally:
                await browser.close()
        import shutil
        for category, *_ in PROFILES:
            target = output / category
            target.mkdir(parents=True, exist_ok=True)
            for file in target.glob("*.png"):
                if not (args.output / category / file.name).exists():
                    file.unlink()
            for file in (args.output / category).glob("*.png"):
                shutil.copyfile(file, target / file.name)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="https://brandonp2412.github.io/stone-and-banner/")
    parser.add_argument("--output", type=Path, default=Path("fastlane/metadata/android/en-US/images"))
    parser.add_argument("--replay", type=Path, help="Capture this replay instead of generating an independent match")
    parser.add_argument("--chromium", default=os.environ.get("CHROMIUM_EXECUTABLE"))
    asyncio.run(main(parser.parse_args()))
