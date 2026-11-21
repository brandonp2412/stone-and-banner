"""Local browser E2E: host + guest + two bots launch a real WebRTC match."""
import asyncio
import os
import signal
import subprocess
import time

from patchright.async_api import async_playwright

ROOT='/home/brandon/stone-and-banner'
SITE='http://127.0.0.1:8766/'
BROWSER='/home/brandon/.cache/ms-playwright/chromium-1228/chrome-linux64/chrome'

async def enable(page):
    await page.locator('flt-semantics-placeholder').evaluate('(el) => el.click()')

async def run():
    async with async_playwright() as p:
        browser=await p.chromium.launch(headless=True,executable_path=BROWSER,args=['--no-sandbox','--disable-dev-shm-usage'])
        hc=await browser.new_context(viewport={'width':1280,'height':800},permissions=['clipboard-read','clipboard-write'])
        host=await hc.new_page()
        await host.goto(SITE,timeout=25000)
        await host.wait_for_timeout(1800)
        await enable(host)
        await host.get_by_text('Host / join multiplayer').click()
        await host.get_by_text('4 players').click()
        await host.get_by_text('Host game',exact=True).click()
        await host.get_by_text('Copy room invitation').wait_for(timeout=20000)
        await host.get_by_text('Copy room invitation').click()
        invite=await host.evaluate('navigator.clipboard.readText()')
        assert invite.startswith(SITE+'#p2p=')
        gc=await browser.new_context(viewport={'width':1280,'height':800})
        guest=await gc.new_page()
        await guest.goto(invite,timeout=25000)
        await guest.wait_for_timeout(1700)
        await enable(guest)
        await guest.get_by_role('textbox').first.fill('HumanGuest')
        await guest.get_by_text('Join game',exact=True).click()
        await guest.get_by_text('Connected to host',exact=False).wait_for(timeout=60000)
        await host.get_by_text('Add AI opponent').click()
        await host.get_by_text('Add AI opponent').click()
        await host.wait_for_timeout(400)
        body=await host.locator('body').inner_text()
        print('HOST LOBBY',body[-2300:],flush=True)
        assert 'Start with 2 AI opponents' in body,body
        assert 'HumanGuest' in body,body
        await host.screenshot(path='/tmp/stone-two-human-two-bots-lobby.png')
        await host.get_by_text('Start with 2 AI opponents').click()
        await host.wait_for_timeout(1800)
        after=await host.locator('body').inner_text()
        gtext=await guest.locator('body').inner_text()
        print('HOST MATCH',after[:1500],flush=True)
        print('GUEST MATCH',gtext[:1300],flush=True)
        assert 'ROUND 1' in after or 'Choose your starting settlement' in after
        assert 'ROUND 1' in gtext or 'Realm map.' in gtext
        assert 'Resume computer' not in after
        assert 'Resume computer' not in gtext
        await host.screenshot(path='/tmp/stone-two-human-two-bots-host-match.png')
        await guest.screenshot(path='/tmp/stone-two-human-two-bots-guest-match.png')
        await browser.close()
        print('PASS 2 humans 2 bots: lobby, encrypted WebRTC, start, no resume button',flush=True)

if __name__ == '__main__':
    srv=subprocess.Popen(['npx','wrangler','dev','--config','wrangler.signalling.jsonc','--port','8799','--ip','127.0.0.1','--local','--inspector-port','0'],
        cwd=ROOT,stdout=open('/tmp/stone-two-human-worker.log','w'),stderr=subprocess.STDOUT,start_new_session=True)
    try:
        time.sleep(2)
        asyncio.run(run())
    finally:
        if srv.poll() is None:os.killpg(srv.pid,signal.SIGTERM)
