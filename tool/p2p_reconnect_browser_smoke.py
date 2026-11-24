"""Exercise real browser WebRTC guest seat recovery, including access control.

Serve a release web build on localhost, then run with Patchright:
  uv run --with patchright python tool/p2p_reconnect_browser_smoke.py
Uses separate fresh browser profiles; does not touch player saves.
"""
import asyncio
import os
from pathlib import Path

from patchright.async_api import async_playwright

SITE = os.environ.get("STONE_TEST_URL", "http://127.0.0.1:8768/")
OUT = Path(os.environ.get("STONE_TEST_SCREENSHOTS", "/tmp/stone-reconnect-screenshots"))


async def enable(page):
    placeholder = page.locator("flt-semantics-placeholder")
    await placeholder.wait_for(state="attached", timeout=30000)
    await placeholder.evaluate("el => el.click()", timeout=15000)


async def body(page):
    await page.bring_to_front()
    return await page.evaluate("document.body.innerText")


async def wait_text(page, value, timeout=45_000):
    await page.bring_to_front()
    await page.wait_for_function("value => document.body.innerText.includes(value)", arg=value, timeout=timeout)


async def capture(page, name):
    await page.screenshot(path=str(OUT / (name + ".png")))


async def main():
    OUT.mkdir(parents=True, exist_ok=True)
    errors = []
    async with async_playwright() as patchright:
        launch = {"headless": True, "args": ["--no-sandbox", "--disable-dev-shm-usage"]}
        if os.environ.get("CHROMIUM_EXECUTABLE"):
            launch["executable_path"] = os.environ["CHROMIUM_EXECUTABLE"]
        browser = await patchright.chromium.launch(**launch)

        async def new_page():
            context = await browser.new_context(viewport={"width": 1440, "height": 900}, permissions=["clipboard-read", "clipboard-write"])
            page = await context.new_page()
            page.on("pageerror", lambda error: errors.append(str(error)))
            return page

        host = await new_page()
        await host.goto(SITE, wait_until="domcontentloaded")
        await enable(host)
        await host.get_by_text("Host / join multiplayer", exact=True).click(timeout=30_000)
        await host.get_by_text("Host game", exact=True).click()
        await host.get_by_text("Copy room invitation", exact=True).click(timeout=40_000)
        invite = await host.evaluate("navigator.clipboard.readText()")
        assert "#p2p=" in invite

        async def join(name):
            page = await new_page()
            await page.goto(invite, wait_until="domcontentloaded")
            await enable(page)
            if name != "Guest":
                field = page.get_by_role("textbox").first
                await field.click()
                await field.press("Control+a")
                await field.press_sequentially(name)
                await page.wait_for_timeout(200)
            await page.get_by_text("Join game", exact=True).click()
            await wait_text(page, "Connected to host")
            return page

        guest = await join("Guest")
        other = await join("OtherGuest")
        await guest.wait_for_timeout(500)
        await capture(guest, "01-guest-lobby")
        await capture(host, "01-full-lobby")
        print("Guest before refresh:", await body(guest), flush=True)
        print("Host before refresh:", await body(host), flush=True)
        token = await guest.evaluate("JSON.parse(sessionStorage.getItem('stone-banner-guest-session-v1')).token")
        assert len(token) == 64

        # A refresh in the lobby must automatically rejoin the same seat.
        await guest.reload(wait_until="domcontentloaded")
        await enable(guest)
        await wait_text(guest, "Connected to host")
        await guest.wait_for_timeout(500)
        await capture(guest, "02-recovered-lobby")
        await capture(host, "02-recovered-host")
        print("Recovered guest:", await body(guest), flush=True)
        print("Host:", await body(host), flush=True)
        assert "Seat 2" in await body(guest)
        print("PASS lobby refresh", flush=True)

        await host.get_by_text("Start multiplayer match", exact=True).click(timeout=10_000)
        for page in (host, guest, other):
            await wait_text(page, "Realm map.")
        await guest.wait_for_timeout(500)
        await capture(guest, "03-match-before-refresh")
        # Make an actual legal board move on whichever human is active.
        for page, name in ((host, "Host"), (guest, "Guest"), (other, "OtherGuest")):
            if "active player " + name in await body(page) and "Your turn" in await body(page):
                # Flutter accessibility's transparent semantics layer intercepts
                # canvas pointer events. Disable it only for this UI click.
                style = await page.add_style_tag(content="flt-semantics { pointer-events: none !important; }")
                await page.mouse.click(336, 156)
                await wait_text(page, "Connect your village")
                await style.evaluate("el => el.remove()")
                break
        else:
            raise AssertionError([await body(page) for page in (host, guest, other)])
        await guest.bring_to_front()
        await guest.wait_for_timeout(500)
        await capture(guest, "04-match-with-placement")
        print("After placement guest:", await body(guest), flush=True)
        print("After placement host:", await body(host), flush=True)

        # An unrelated browser with the public invitation and same name must
        # not gain access to this already-started room.
        stranger = await new_page()
        await stranger.goto(invite, wait_until="domcontentloaded")
        await enable(stranger)
        await stranger.get_by_text("Join game", exact=True).click()
        await wait_text(stranger, "Room has no available player seats")
        assert "Realm map." not in await body(stranger)
        await capture(stranger, "05-unauthorized-guest-rejected")
        print("PASS same-name stranger cannot reclaim seat", flush=True)

        # Repeated refreshes retain identity, score and authoritative state.
        for index in range(2):
            await guest.reload(wait_until="domcontentloaded")
            await enable(guest)
            await wait_text(guest, "Realm map.")
            await guest.wait_for_timeout(500)
            await capture(guest, f"06-recovered-match-{index}")
            text = await body(guest)
            print("Recovered match:", text, flush=True)
            assert "Guest" in text and "1 of 15 Renown" in text, text
            saved = await guest.evaluate("JSON.parse(sessionStorage.getItem('stone-banner-guest-session-v1'))")
            assert saved["token"] == token and saved["name"] == "Guest"
        print("PASS repeated live-match refresh, original seat and current board retained", flush=True)
        assert not errors, errors
        print("PASS no browser exceptions", flush=True)
        await browser.close()


if __name__ == "__main__":
    asyncio.run(main())
