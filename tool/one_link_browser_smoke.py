import asyncio
import os
import signal
import subprocess
import time

from patchright.async_api import async_playwright

ROOT = "/home/brandon/stone-and-banner"
SITE = "http://127.0.0.1:8766/"
WORKER = "ws://127.0.0.1:8799/signal/"
BROWSER = "/home/brandon/.cache/ms-playwright/chromium-1228/chrome-linux64/chrome"

async def enable_semantics(page):
    await page.locator("flt-semantics-placeholder").evaluate("(el) => el.click()")

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True, executable_path=BROWSER, args=["--no-sandbox"])
        ctx = await browser.new_context(viewport={"width":1280,"height":800}, permissions=["clipboard-read","clipboard-write"])
        host = await ctx.new_page()
        host.on("pageerror", lambda e: print("HOST PAGE ERROR",e,flush=True))
        await host.goto(SITE, timeout=20000)
        await host.wait_for_timeout(2500)
        await enable_semantics(host)
        await host.get_by_text("Host / join multiplayer").click()
        print("SETUP:", (await host.locator("body").inner_text())[:1500],flush=True)
        await host.get_by_text("Host game",exact=True).click()
        try:
            await host.get_by_text("Copy room invitation").wait_for(timeout=16000)
        except Exception:
            print("HOST FAILED:",(await host.locator("body").inner_text())[:2000],flush=True)
            await host.screenshot(path="/tmp/stone-one-link-host-failed.png")
            raise
        await host.screenshot(path="/tmp/stone-one-link-host.png")
        print("HOST:",(await host.locator("body").inner_text())[:2500],flush=True)
        await host.get_by_text("Copy room invitation").click()
        invite = await host.evaluate("navigator.clipboard.readText()")
        print("INVITE:",invite[:85],"length",len(invite),flush=True)
        assert invite.startswith(SITE + "#p2p=")

        guest_ctx = await browser.new_context(viewport={"width":1280,"height":800})
        guest = await guest_ctx.new_page()
        guest.on("pageerror", lambda e: print("GUEST PAGE ERROR",e,flush=True))
        await guest.goto(invite, timeout=20000)
        await guest.wait_for_timeout(2600)
        await enable_semantics(guest)
        print("GUEST BEFORE:",(await guest.locator("body").inner_text())[:1300],flush=True)
        await guest.get_by_text("Join game",exact=True).click()
        try:
            await guest.get_by_text("Connected to host",exact=False).wait_for(timeout=65000)
            # Open the exact SAME link in a second independent browser profile.
            guest2_ctx = await browser.new_context(viewport={"width":1280,"height":800})
            guest2 = await guest2_ctx.new_page()
            await guest2.goto(invite, timeout=20000)
            await guest2.wait_for_timeout(2000)
            await enable_semantics(guest2)
            print("SECOND TEXTBOXES",await guest2.get_by_role("textbox").count(),flush=True)
            await guest2.get_by_role("textbox").first.fill("Bob")
            await guest2.get_by_text("Join game",exact=True).click()
            await guest2.get_by_text("Connected to host",exact=False).wait_for(timeout=65000)
            await host.bring_to_front()
            await host.wait_for_timeout(1200)
            print("HOST PLAYERS:",(await host.locator("body").inner_text())[:1500],flush=True)
            assert "Bob" in await host.locator("body").inner_text()
            await host.screenshot(path="/tmp/stone-one-link-host-two-guests.png")
            await guest2.screenshot(path="/tmp/stone-one-link-guest2.png")
            await host.get_by_text("Start multiplayer match").click()
            await host.wait_for_timeout(1200)
            print("GUEST AFTER:",(await guest.locator("body").inner_text())[:1300],flush=True)
            print("HOST AFTER:",(await host.locator("body").inner_text())[:2000],flush=True)
            print("PASS: same reusable link connects two guests; host can start",flush=True)
        finally:
            await guest.screenshot(path="/tmp/stone-one-link-guest.png")
            await host.screenshot(path="/tmp/stone-one-link-host-after.png")
        await browser.close()

if __name__ == "__main__":
    worker = subprocess.Popen(
        ["npx","--yes","wrangler","dev","--config","wrangler.signalling.jsonc",
         "--port","8799","--ip","127.0.0.1","--local","--inspector-port","0"],
        cwd=ROOT,stdout=open("/tmp/stone-signal-worker.log","w"),stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    try:
        time.sleep(2)
        asyncio.run(main())
    finally:
        if worker.poll() is None:
            os.killpg(worker.pid,signal.SIGTERM)
