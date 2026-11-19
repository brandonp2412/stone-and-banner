// node --test tool/p2p_ice_test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

function browserHarness(withPublicCandidate, {gathering = false} = {}) {
  const calls = [];
  const configs = [];
  const candidates = withPublicCandidate
    ? 'a=candidate:1 1 udp 123 203.0.113.10 5555 typ srflx\r\n'
    : 'a=candidate:1 1 udp 123 10.0.0.2 5555 typ host\r\n';

  class FakeConnection {
    constructor(configuration) {
      configs.push(configuration);
      this.iceGatheringState = gathering ? 'gathering' : 'complete';
      this.connectionState = 'new';
      this.listeners = new Map();
      this.localDescription = null;
    }
    createDataChannel() { return {readyState: 'connecting', close() {}}; }
    createOffer() { return Promise.resolve({type: 'offer', sdp: 'v=0\r\n'}); }
    async setLocalDescription(description) {
      this.localDescription = {...description, sdp: description.sdp + candidates};
    }
    addEventListener(type, handler) { this.listeners.set(type, handler); }
    removeEventListener(type) { this.listeners.delete(type); }
    close() {}
  }

  const browser = {RTCPeerConnection: FakeConnection};
  const context = {
    window: browser,
    RTCPeerConnection: FakeConnection,
    location: {hash: '', href: 'https://example.test/stone-and-banner/'},
    setTimeout,
    clearTimeout,
  };
  const source = fs.readFileSync(path.resolve(__dirname, '../web/p2p.js'), 'utf8');
  vm.runInNewContext(source, context);
  return {browser, configs, calls};
}

test('public STUN adds only direct candidates, without TURN or relays', async () => {
  const {browser, configs} = browserHarness(true);
  const events = [];
  browser.stoneP2p.create('player-1', true, (event, data) => events.push([event, data]));
  const offer = JSON.parse(await browser.stoneP2p.offer('player-1'));
  assert.equal(offer.type, 'offer');
  assert.match(offer.sdp, /typ srflx/);
  assert.equal(configs.length, 1);
  assert.equal(configs[0].iceTransportPolicy, 'all');
  const urls = configs[0].iceServers.flatMap(server => server.urls);
  assert.ok(urls.includes('stun:stun.l.google.com:19302'));
  assert.ok(urls.includes('stun:stun.cloudflare.com:3478'));
  assert.ok(urls.every(url => url.startsWith('stun:')));
  assert.match(events.find(([event]) => event === 'diagnostic')[1], /Public STUN candidate found/);
  browser.stoneP2p.close('player-1');
});

test('unavailable public candidate keeps local connectivity instead of failing', async () => {
  const {browser} = browserHarness(false);
  const events = [];
  browser.stoneP2p.create('player-2', true, (event, data) => events.push([event, data]));
  const offer = JSON.parse(await browser.stoneP2p.offer('player-2'));
  assert.match(offer.sdp, /typ host/);
  assert.match(events.find(([event]) => event === 'diagnostic')[1], /Only local candidates/);
  browser.stoneP2p.close('player-2');
});

test('public candidate stops waiting for missing ICE gathering completion', async () => {
  const {browser} = browserHarness(true, {gathering: true});
  browser.stoneP2p.create('player-3', true, () => {});
  const started = performance.now();
  const result = JSON.parse(await browser.stoneP2p.offer('player-3'));
  assert.match(result.sdp, /typ srflx/);
  assert.ok(performance.now() - started < 2500, 'public offer should finish quickly');
  browser.stoneP2p.close('player-3');
});
