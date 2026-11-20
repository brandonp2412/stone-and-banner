// node --test tool/p2p_ice_test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

function browserHarness(withPublicCandidate, {gathering = false} = {}) {
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
    createOffer() { return Promise.resolve({type: 'offer', sdp: 'v=0\r\n'}); }
    createAnswer() { return Promise.resolve({type: 'answer', sdp: 'v=0\r\n'}); }
    async setRemoteDescription(description) { this.remoteDescription = description; }
    async getStats() {
      return new Map([['pair', {type: 'candidate-pair', state: 'in-progress',
        requestsSent: 202, requestsReceived: 0, responsesReceived: 0}]]);
    }
    async setLocalDescription(description) {
      this.localDescription = {...description, sdp: description.sdp + candidates};
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

test('carrier NAT port-dependent mappings enable bounded direct-only UDP alternatives', async () => {
  const {browser, connections} = browserHarness(true);
  browser.stoneP2p.create('cellular-guest', false, () => {});
  const sdp = 'v=0\r\n' +
    'a=candidate:1 1 udp 1680000000 203.0.113.20 33330 typ srflx raddr 100.70.80.9 rport 48576\r\n' +
    'a=candidate:2 1 udp 1680000000 203.0.113.20 33308 typ srflx raddr 100.70.80.9 rport 48576\r\n' +
    'a=end-of-candidates\r\n';
  const answer = JSON.parse(await browser.stoneP2p.answer('cellular-guest',
    JSON.stringify({type: 'offer', sdp})));
  assert.equal(answer.type, 'answer');
  // Inspect the SDP applied to the guest, rather than just a helper return.
  // Each alternative retains the real ICE credentials, IP and protocol.
  const remote = connections[0].remoteDescription;
  assert.equal(remote.type, 'offer');
  const candidates = remote.sdp.split('\r\n').filter(row => row.startsWith('a=candidate:'));
  assert.ok(candidates.length > 100 && candidates.length < 300, 'bounded extra candidates');
  assert.ok(candidates.some(row => row.includes(' 203.0.113.20 33329 typ srflx')));
  assert.ok(candidates.some(row => row.includes(' 203.0.113.20 33331 typ srflx')));
  assert.ok(candidates.every(row => !row.includes('typ relay')));
  assert.equal(candidates.at(-1).includes('raddr 100.70.80.9 rport 48576'), true);
  const report = JSON.parse(await browser.stoneP2p.diagnostics('cellular-guest'));
  assert.ok(report.carrierNatProbeCandidates > 100);
  assert.equal(report.connectivityChecks.requestsSent, 202);
  assert.equal(report.connectivityChecks.responsesReceived, 0);
  assert.ok(!JSON.stringify(report).includes('203.0.113.20'));
});

test('no candidate probing on ordinary single-mapping LAN or STUN offers', async () => {
  const {browser, connections} = browserHarness(true);
  const reports = [];
  browser.stoneP2p.create('ordinary-guest', false, (event, data) => reports.push([event, data]));
  await browser.stoneP2p.answer('ordinary-guest', JSON.stringify({type: 'offer', sdp:
    'v=0\r\na=candidate:1 1 udp 123 192.168.1.10 44300 typ host\r\n' +
    'a=candidate:2 1 udp 123 203.0.113.20 33330 typ srflx raddr 100.70.80.9 rport 48576\r\n'}));
  assert.ok(!reports.some(([event, data]) => event === 'diagnostic' && /endpoint-dependent/i.test(data)));
  assert.equal(connections[0].remoteDescription.sdp.split('a=candidate:').length - 1, 2);
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

test('a private WireGuard address is persisted and added as an extra candidate', async () => {
  const {browser, storage} = browserHarness(false);
  browser.stoneP2p.setDirectAddress('10.66.66.3');
  assert.equal(browser.stoneP2p.directAddress(), '10.66.66.3');
  browser.stoneP2p.create('wireguard', true, () => {});
  const offer = JSON.parse(await browser.stoneP2p.offer('wireguard'));
  assert.match(offer.sdp, /10\.0\.0\.2 5555 typ host/);
  assert.match(offer.sdp, /10\.66\.66\.3 5555 typ host/);
  assert.equal(storage.get('stone-banner-p2p-direct-address'), '10.66.66.3');
  browser.stoneP2p.close('wireguard');
  browser.stoneP2p.setDirectAddress('');
  assert.equal(storage.has('stone-banner-p2p-direct-address'), false);
});

test('invalid or public address hints are rejected without changing configuration', () => {
  const {browser} = browserHarness(false);
  for (const address of ['8.8.8.8', '999.168.1.1', '127.0.0.1', '10.66.66.0', '10.66.66.255']) {
    assert.throws(() => browser.stoneP2p.setDirectAddress(address), /private IPv4/);
  }
  browser.stoneP2p.setDirectAddress('192.168.1.102');
  assert.equal(browser.stoneP2p.directAddress(), '192.168.1.102');
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
  assert.equal(report.privateAddressHintConfigured, false);
  assert.ok(!raw.includes('10.0.0.2'));
  assert.ok(!raw.includes('a=candidate'));
  browser.stoneP2p.close('diagnostic-test');
});
