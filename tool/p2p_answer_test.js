// node --test tool/p2p_answer_test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const bridgeSource = fs.readFileSync(path.join(__dirname, '../web/p2p.js'), 'utf8');

function makeBrowser(bus) {
  const listeners = new Map();
  const location = {
    hash: '',
    href: 'https://brandonp2412.github.io/stone-and-banner/',
    pathname: '/stone-and-banner/',
    search: '',
  };
  const history = {
    state: {},
    replaced: [],
    replaceState(_state, _title, url) {
      this.replaced.push(url);
      location.hash = '';
      location.href = 'https://brandonp2412.github.io' + url;
    },
  };
  class Channel {
    constructor(name) {
      this.name = name;
      this.callbacks = [];
      bus.add(this);
    }
    addEventListener(event, handler) {
      assert.equal(event, 'message');
      this.callbacks.push(handler);
    }
    postMessage(message) {
      for (const other of bus) {
        if (other !== this && other.name === this.name) {
          for (const handler of other.callbacks) handler({data: message});
        }
      }
    }
  }
  const browser = {
    addEventListener(type, handler) { listeners.set(type, handler); },
  };
  let nextTimer = 0;
  const intervals = new Map();
  const context = {
    window: browser, location, history, BroadcastChannel: Channel,
    crypto: {randomUUID: () => 'receipt-' + Math.random()},
    atob, setTimeout, clearTimeout,
    setInterval(fn) {const id = ++nextTimer; intervals.set(id, fn); return id;},
    clearInterval(id) { intervals.delete(id); },
  };
  vm.runInNewContext(bridgeSource, context);
  return {api: browser.stoneP2p, location, history, listeners, intervals};
}

test('two tabs require a real host acknowledgement before reporting success', async () => {
  const bus = new Set();
  const host = makeBrowser(bus);
  const replyTab = makeBrowser(bus);
  const answer = 'https://brandonp2412.github.io/stone-and-banner/#p2p=abc';
  const received = [];
  host.api.onAnswer((link, receiptId) => {
    received.push(link);
    host.api.acknowledgeAnswer(receiptId, true);
  });
  const accepted = await replyTab.api.forwardAnswer(answer);
  assert.equal(accepted, true);
  assert.deepEqual(received, [answer]);
  assert.equal(replyTab.intervals.size, 0);
});

test('an unrelated response tab is not falsely marked delivered', async () => {
  const bus = new Set();
  const guest = makeBrowser(bus);
  const response = guest.api.forwardAnswer('https://example.test/#p2p=abc');
  assert.equal(guest.intervals.size, 1);
  // Simulate the retry budget without waiting for wall-clock time.
  for (let i = 0; i < 5; i++) {
    const timer = [...guest.intervals.values()][0];
    if (timer) timer();
  }
  assert.equal(await response, false);
  assert.equal(guest.intervals.size, 0);
});

test('a response opened in the original host tab does not destroy it', () => {
  const bus = new Set();
  const host = makeBrowser(bus);
  const received = [];
  host.api.setHosting(true);
  host.api.onAnswer((link, receiptId) => received.push({link, receiptId}));
  const encoded = Buffer.from(JSON.stringify({type: 'answer'})).toString('base64url');
  const reply = 'https://brandonp2412.github.io/stone-and-banner/#p2p=' + encoded;
  host.location.href = reply;
  host.location.hash = '#p2p=' + encoded;
  host.listeners.get('hashchange')();
  assert.deepEqual(received, [{link: reply, receiptId: ''}]);
  assert.deepEqual(host.history.replaced, ['/stone-and-banner/']);
  assert.equal(host.location.hash, '');
});
