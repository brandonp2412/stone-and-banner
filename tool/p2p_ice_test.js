// node --test tool/p2p_ice_test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

function browserHarness(withPublicCandidate, {gathering = false, relay = false} = {}) {
  const calls = [];
  const configs = [];
  const connections = [];
  const storage = new Map();
  const candidates = withPublicCandidate
    ? 'a=candidate:1 1 udp 123 203.0.113.10 5555 typ srflx\r\n'
    : 'a=candidate:1 1 udp 123 10.0.0.2 5555 typ host\r\n';

  class FakeConnection {
    constructor(configuration) {
      configs.push(configuration);
      connections.push(this);
      this.iceGatheringState = gathering ? 'gathering' : 'complete';
      this.connectionState = 'new';
      this.listeners = new Map();
      this.localDescription = null;
    }
    createDataChannel() { return {readyState: 'connecting', close() {}}; }
    setConfiguration(config) { this.configuration = config; }
    createOffer() { return Promise.resolve({type: 'offer', sdp: 'v=0\r\n'}); }
    createAnswer() { return Promise.resolve({type: 'answer', sdp: 'v=0\r\n'}); }
    async setRemoteDescription(description) { this.remoteDescription = description; }
    async getStats() {
      return new Map([['pair', {type: 'candidate-pair', state: 'in-progress',
        requestsSent: 202, requestsReceived: 0, responsesReceived: 0}]]);
    }
    async setLocalDescription(description) {
      this.localDescription = {...description, sdp: description.sdp + candidates +
        (relay ? 'a=candidate:2 1 udp 100 192.0.2.2 3478 typ relay\r\n' : '')};
    }
    addEventListener(type, handler) { this.listeners.set(type, handler); }
    removeEventListener(type) { this.listeners.delete(type); }
    close() {}
  }

  const browser = {RTCPeerConnection: FakeConnection, addEventListener() {}};
  const context = {
    window: browser,
    RTCPeerConnection: FakeConnection,
    location: {hash: '', href: 'https://example.test/stone-and-banner/'},
    setTimeout,
    clearTimeout,
    ...(relay ? {fetch: async () => ({ok: true, json: async () => ({iceServers: [
      {urls: 'stun:stun.l.google.com:19302'},
      {urls: 'turn:global.relay.metered.ca:80', username: 'test-user', credential: 'test-pass'},
    ]})})} : {}),
    localStorage: {
      getItem: key => storage.get(key) ?? null,
      setItem: (key, value) => storage.set(key, value),
      removeItem: key => storage.delete(key),
    },
  };
  const source = fs.readFileSync(path.resolve(__dirname, '../web/p2p.js'), 'utf8');
  vm.runInNewContext(source, context);
  return {browser, configs, calls, storage, connections};
}

test('an offer is accepted unchanged without speculative NAT port probing', async () => {
  const {browser, connections} = browserHarness(true);
  browser.stoneP2p.create('cellular-guest', false, () => {});
  const sdp = 'v=0\r\n' +
    'a=candidate:1 1 udp 1680000000 203.0.113.20 33330 typ srflx raddr 100.70.80.9 rport 48576\r\n' +
    'a=candidate:2 1 udp 1680000000 203.0.113.20 33308 typ srflx raddr 100.70.80.9 rport 48576\r\n';
  const answer = JSON.parse(await browser.stoneP2p.answer('cellular-guest',
    JSON.stringify({type: 'offer', sdp})));
  assert.equal(answer.type, 'answer');
  assert.equal(connections[0].remoteDescription.sdp, sdp);
  const report = JSON.parse(await browser.stoneP2p.diagnostics('cellular-guest'));
  assert.equal(report.connectivityChecks.requestsSent, 202);
  assert.ok(!JSON.stringify(report).includes('203.0.113.20'));
});

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
  assert.ok(events.some(([event, data]) => event === 'diagnostic' && /Public STUN candidate found/.test(data)));
  browser.stoneP2p.close('player-1');
});

test('free relay is configured before offer and candidates are embedded in manual SDP', async () => {
  const {browser, connections} = browserHarness(true, {relay: true});
  const events = [];
  browser.stoneP2p.create('relay-player', true, (event, data) => events.push([event, data]));
  const offer = JSON.parse(await browser.stoneP2p.offer('relay-player'));
  assert.match(offer.sdp, /typ relay/);
  assert.ok(connections[0].configuration.iceServers.some(server =>
    server.urls.startsWith('turn:')));
  assert.ok(events.some(([event, data]) => event === 'diagnostic' &&
    data.includes('TURN relay candidate gathered')));
  assert.equal(JSON.parse(await browser.stoneP2p.diagnostics('relay-player')).relayConfigured, true);
  browser.stoneP2p.close('relay-player');
});

test('unavailable public candidate keeps local connectivity instead of failing', async () => {
  const {browser} = browserHarness(false);
  const events = [];
  browser.stoneP2p.create('player-2', true, (event, data) => events.push([event, data]));
  const offer = JSON.parse(await browser.stoneP2p.offer('player-2'));
  assert.match(offer.sdp, /typ host/);
  assert.ok(events.some(([event, data]) => event === 'diagnostic' && /Only local candidates/.test(data)));
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

test('control-only WireGuard candidates are excluded from shared offers', async () => {
  const {browser, connections} = browserHarness(false);
  browser.stoneP2p.create('cellular-player', true, () => {});
  const peer = connections[0];
  await browser.stoneP2p.offer('cellular-player');
  peer.localDescription.sdp += 'a=candidate:77 1 udp 123 10.66.66.3 3344 typ host\r\n';
  const safe = JSON.parse(await (async () => {
    // Generate a second offer with the native SDP candidate injected by the fake.
    peer.setLocalDescription = async description => {
      peer.localDescription = {...description, sdp: description.sdp +
        'a=candidate:77 1 udp 123 10.66.66.3 3344 typ host\r\n' +
        'a=candidate:2 1 udp 123 192.168.1.4 3344 typ host\r\n'};
    };
    return browser.stoneP2p.offer('cellular-player');
  })());
  assert.doesNotMatch(safe.sdp, /10\.66\.66\./);
  assert.match(safe.sdp, /192\.168\.1\.4/);
  assert.equal(typeof browser.stoneP2p.setDirectAddress, 'undefined');
  browser.stoneP2p.close('cellular-player');
});

test('guest does not report an ICE failure before host applies the response', async () => {
  const {browser, connections} = browserHarness(true);
  const events = [];
  browser.stoneP2p.create('pending-guest', false, (event, data) => events.push([event, data]));
  connections[0].connectionState = 'failed';
  connections[0].onconnectionstatechange();
  assert.ok(!events.some(([event]) => event === 'error'), 'host has not received reply yet');
  connections[0].connectionState = 'connected';
  connections[0].onconnectionstatechange();
  browser.stoneP2p.close('pending-guest');
  assert.ok(!events.some(([event]) => event === 'error'));
});

test('host errors only after applying a guest response and an ICE failure', async () => {
  const {browser, connections} = browserHarness(true);
  const events = [];
  browser.stoneP2p.create('pending-host', true, (event, data) => events.push([event, data]));
  connections[0].connectionState = 'failed';
  connections[0].onconnectionstatechange();
  assert.ok(!events.some(([event]) => event === 'error'));
  connections[0].remoteDescription = {type: 'answer', sdp: 'v=0\r\n'};
  connections[0].onconnectionstatechange();
  assert.ok(events.some(([event, data]) => event === 'error' && data.includes('ICE failed')));
  browser.stoneP2p.close('pending-host');
});

test('temporary ICE disconnect does not evict a connected guest', () => {
  const {browser, connections} = browserHarness(true);
  const events = [];
  browser.stoneP2p.create('brief-drop', true, (event) => events.push(event));
  connections[0].connectionState = 'connected';
  connections[0].onconnectionstatechange();
  connections[0].connectionState = 'disconnected';
  connections[0].onconnectionstatechange();
  assert.ok(!events.includes('close'), 'ICE can recover after browser suspension');
  connections[0].connectionState = 'connected';
  connections[0].onconnectionstatechange();
  assert.ok(!events.includes('close'), 'recovery must cancel eviction');
  browser.stoneP2p.close('brief-drop');
});

test('support diagnostics include candidate types, never raw IPs or SDP', async () => {
  const {browser} = browserHarness(false);
  browser.stoneP2p.create('diagnostic-test', true, () => {});
  await browser.stoneP2p.offer('diagnostic-test');
  const raw = await browser.stoneP2p.diagnostics('diagnostic-test');
  const report = JSON.parse(raw);
  assert.equal(report.engine, 'browser WebRTC');
  assert.equal(report.localCandidates.length, 1);
  assert.equal(report.localCandidates[0].type, 'host');
  assert.equal(report.localCandidates[0].protocol, 'udp');
  assert.equal(report.localCandidates[0].privateIPv4, true);
  assert.equal(report.relayConfigured, false);
  assert.ok(!raw.includes('10.0.0.2'));
  assert.ok(!raw.includes('a=candidate'));
  browser.stoneP2p.close('diagnostic-test');
});
