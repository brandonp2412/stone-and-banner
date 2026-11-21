// Covers connection setup and recovery on the real deployed Durable Object.
// Run with SIGNAL_TEST_ENDPOINT=wss://.../signal/ node tool/signal_worker_smoke.mjs
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';

const endpoint = process.env.SIGNAL_TEST_ENDPOINT ?? 'ws://127.0.0.1:8799/signal/';
const freshKey = () => randomBytes(16).toString('hex');
const clients = [];

function connect(role, key) {
  const socket = new WebSocket(endpoint + key + '?role=' + role);
  clients.push(socket);
  const queue = [];
  const listeners = [];
  socket.onmessage = ({data}) => {
    const msg = JSON.parse(data);
    const i = listeners.findIndex(x => x.op === msg.op);
    if (i >= 0) listeners.splice(i, 1)[0].resolve(msg);
    else queue.push(msg);
  };
  const ready = new Promise((resolve, reject) => {
    socket.onopen = resolve;
    socket.onerror = () => reject(new Error('WebSocket handshake refused for ' + role));
  });
  function receive(op, timeoutMs = 12000) {
    const i = queue.findIndex(x => x.op === op);
    if (i >= 0) return Promise.resolve(queue.splice(i, 1)[0]);
    return new Promise((resolve, reject) => {
      const target = {op, resolve};
      listeners.push(target);
      setTimeout(() => {
        const i = listeners.indexOf(target);
        if (i >= 0) {
          listeners.splice(i, 1);
          reject(new Error('Timed out waiting for ' + op + ' from ' + role));
        }
      }, timeoutMs).unref?.();
    });
  }
  return {
    socket, ready, receive,
    send: x => socket.send(JSON.stringify(x)),
    close: () => socket.close(),
  };
}

try {
  const key = freshKey();
  const host = connect('host', key);
  await host.ready;
  await host.receive('ready');
  host.send({op:'host_ready'});
  const guest = connect('guest', key);
  await guest.ready;
  const peer = (await guest.receive('ready')).peer;
  assert.equal((await host.receive('join')).peer, peer);
  host.send({op:'offer', peer, room:'1A2B3C4D', sdp:'sdp offer'});
  assert.equal((await guest.receive('offer')).sdp, 'sdp offer');
  guest.send({op:'answer',peer:'spoofed',sdp:'sdp answer'});
  assert.equal((await host.receive('answer')).peer, peer);
  host.send({op:'ping'});
  assert.equal((await host.receive('pong')).op, 'pong');
  console.log('PASS normal room, offer/answer, identity, heartbeat');

  const waitingKey = freshKey();
  const statusUrl = endpoint.replace(/^wss:/, 'https:').replace(/^ws:/, 'http:') + 'status/' + waitingKey;
  const absentResponse = await fetch(statusUrl, {headers:{Origin:'https://brandonp2412.github.io'}});
  assert.equal(absentResponse.status, 200);
  assert.equal(absentResponse.headers.get('access-control-allow-origin'),'https://brandonp2412.github.io');
  const absentStatus = await absentResponse.json();
  assert.equal(absentStatus.state,'host_absent');
  assert.equal(absentStatus.protocol,2);
  const earlyGuest = connect('guest', waitingKey);
  await earlyGuest.ready;
  const earlyPeer = (await earlyGuest.receive('ready')).peer;
  assert.equal((await earlyGuest.receive('waiting')).code, 'host_offline');
  const lateHost = connect('host', waitingKey);
  await lateHost.ready;
  await lateHost.receive('ready');
  lateHost.send({op:'host_ready'});
  assert.equal((await earlyGuest.receive('host_online')).op, 'host_online');
  const onlineStatus = await (await fetch(statusUrl)).json();
  assert.equal(onlineStatus.state, 'host_ready');
  assert.equal(onlineStatus.hostSocketCount, 1);
  assert.equal((await lateHost.receive('join')).peer, earlyPeer);
  lateHost.send({op:'offer',peer:earlyPeer,room:'99CFFF00',sdp:'retry offer'});
  assert.equal((await earlyGuest.receive('offer')).sdp, 'retry offer');
  lateHost.close();
  assert.equal((await earlyGuest.receive('waiting')).code,'host_offline');
  const offlineStatus = await (await fetch(statusUrl)).json();
  assert.equal(offlineStatus.state, 'host_absent');
  // Closed sockets must be purged from the room before reconnection.
  await new Promise(resolve => setTimeout(resolve, 1000));
  const returnHost = connect('host', waitingKey);
  await returnHost.ready;
  assert.equal((await returnHost.receive('ready')).op, 'ready');
  returnHost.send({op:'host_ready'});
  assert.equal((await returnHost.receive('join')).peer,earlyPeer);
  console.log('PASS guest before host, host disconnect, same-link reconnect');

  // Previously installed clients don't send host_ready. Preserve their
  // ability to host on the new Worker without forcing app updates.
  const legacyKey = freshKey();
  const legacyHost = connect('host', legacyKey);
  await legacyHost.ready;
  await legacyHost.receive('ready');
  const legacyGuest = connect('guest', legacyKey);
  await legacyGuest.ready;
  const legacyPeer = (await legacyGuest.receive('ready')).peer;
  assert.equal((await legacyGuest.receive('waiting')).op, 'waiting');
  assert.equal((await legacyHost.receive('join', 7000)).peer, legacyPeer);
  console.log('PASS legacy host without host_ready still accepts guests');

  const fullKey = freshKey();
  const fullHost = connect('host', fullKey);
  await fullHost.ready;
  await fullHost.receive('ready');
  fullHost.send({op:'host_ready'});
  for (let i=0; i<3; i++) {
    const client = connect('guest', fullKey);
    await client.ready;
    await client.receive('ready');
    await fullHost.receive('join');
  }
  const overflow = connect('guest', fullKey);
  await overflow.ready;
  const denial = await overflow.receive('error');
  assert.equal(denial.code, 'room_full');
  console.log('PASS room-full diagnostic through successful WebSocket upgrade');
} finally {
  for (const client of clients) {
    try {client.close();} catch {}
  }
}
