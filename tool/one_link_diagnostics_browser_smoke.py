"""Local browser E2E: failed WebSocket + reachable Worker status probe."""
import asyncio
import base64
import json
import threading
from http.server import BaseHTTPRequestHandler, SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from patchright.async_api import async_playwright

ROOT = Path('/home/brandon/stone-and-banner')
KEY = '1234567890abcdef1234567890abcdef'
SITE = 'http://127.0.0.1:8892/'

class WorkerHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith('/signal/status/'):
            body = json.dumps({
                'protocol': 2,
                'state': 'host_ready',
                'hostSocketCount': 1,
                'pendingGuests': 0,
            }).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Access-Control-Expose-Headers', 'CF-Ray')
            self.send_header('CF-Ray', 'deadbeef-AKL')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            body = b'Cloudflare-style failed handshake'
            self.send_response(503)
            self.send_header('Content-Length',str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    def log_message(self, *args): pass

class WebsiteHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT / 'build/web'), **kwargs)
    def log_message(self, *args): pass

async def run():
    encoded = base64.urlsafe_b64encode(json.dumps(
        {'v':2,'type':'room','key':KEY}, separators=(',',':')
    ).encode()).decode().rstrip('=')
    async with async_playwright() as p:
        browser = await p.chromium.launch(
            headless=True,
            executable_path='/home/brandon/.cache/ms-playwright/chromium-1228/chrome-linux64/chrome',
            args=['--no-sandbox','--disable-dev-shm-usage'],
        )
        context = await browser.new_context(
            viewport={'width':1200,'height':800},
            permissions=['clipboard-read','clipboard-write'],
        )
        page = await context.new_page()
        await page.goto(SITE + '#p2p=' + encoded, timeout=20000)
        await page.wait_for_timeout(2500)
        await page.locator('flt-semantics-placeholder').evaluate('(el) => el.click()')
        await page.get_by_text('Join game', exact=True).click()
        await page.get_by_text('Copy diagnostics', exact=True).wait_for(timeout=25000)
        await page.get_by_text('Copy diagnostics', exact=True).click()
        await page.wait_for_timeout(350)
        report=json.loads(await page.evaluate('navigator.clipboard.readText()'))
        trace=report.get('signallingTrace',[])
        print('DIAGNOSTIC SUMMARY',json.dumps({
            'status':report.get('status'),
            'events':[x.get('event') for x in trace],
            'probe':[x for x in trace if x.get('event')=='http_probe'],
            'uiError':report.get('uiError'),
        }),flush=True)
        assert report['status']['activePeerConnections']==0
        assert len([x for x in trace if x['event']=='connect_attempt'])==3
        assert len([x for x in trace if x['event']=='connect_attempt_failed'])==3
        probes=[x for x in trace if x['event']=='http_probe']
        assert probes and probes[-1]['httpStatus']==200, probes
        assert probes[-1]['roomState']=='host_ready',probes
        assert probes[-1]['serverProtocol']==2,probes
        assert probes[-1]['cloudflareRay']=='deadbeef-AKL',probes
        assert KEY not in json.dumps(report), 'Private room key leaked in diagnostics'
        await page.screenshot(path='/tmp/stone-diagnostic-websocket-503.png')
        print('PASS: browser reports 503 WebSocket failure, preserves HTTP 200 host-ready evidence, redacts key',flush=True)
        await browser.close()

if __name__ == '__main__':
    worker=ThreadingHTTPServer(('127.0.0.1',8891),WorkerHandler)
    site=ThreadingHTTPServer(('127.0.0.1',8892),WebsiteHandler)
    threads=[threading.Thread(target=s.serve_forever,daemon=True) for s in [worker,site]]
    for thread in threads:thread.start()
    try:asyncio.run(run())
    finally:
        worker.shutdown()
        site.shutdown()
