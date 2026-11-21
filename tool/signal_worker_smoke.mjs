// Integration smoke for the real local Miniflare Durable Object.
import assert from 'node:assert/strict';

const endpoint = process.env.SIGNAL_TEST_ENDPOINT ?? 'ws://127.0.0.1:8799/signal/';
const key = '00112233445566778899aabbccddeeff';
function connect(role) {
  const socket = new WebSocket(endpoint + key + '?role=' + role);
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
    socket.onerror = () => reject(new Error('WebSocket handshake refused'));
  });
  function receive(op, timeoutMs = 5000) {
    const i = queue.findIndex(x => x.op === op);
    if (i >= 0) return Promise.resolve(queue.splice(i, 1)[0]);
    return new Promise((resolve, reject) => {
      const target = {op, resolve};
      listeners.push(target);
      setTimeout(() => {
        const i = listeners.indexOf(target);
        if (i >= 0) { listeners.splice(i, 1); reject(new Error('Timed out waiting for ' + op)); }
      }, timeoutMs).unref?.();
    });
  }
  return {socket, ready, receive, send: x => socket.send(JSON.stringify(x))};
}
const host = connect('host');
await host.ready;
assert.equal((await host.receive('ready')).op, 'ready');
const guest = connect('guest');
await guest.ready;
const guestId = (await guest.receive('ready')).peer;
assert.equal(typeof guestId, 'string');
assert.equal((await host.receive('join')).peer, guestId);
const exampleSdp = '{"type":"offer","sdp":"small-test"}';
host.send({op: 'offer', peer:guestId, room:'1A2B3C4D', sdp:exampleSdp});
assert.equal((await guest.receive('offer')).sdp, exampleSdp);
guest.send({op: 'answer', sdp:'{"type":"answer","sdp":"small-test"}', peer:'spoofed'});
const received = await host.receive('answer');
assert.equal(received.peer, guestId, 'server must use socket identity not spoofed peer');
const guest2 = connect('guest');
await guest2.ready;
const guest2Id = (await guest2.receive('ready')).peer;
assert.equal(typeof guest2Id, 'string');
assert.equal((await host.receive('join')).op, 'join');
host.send({op:'reject', peer:guest2Id});
assert.equal((await guest2.receive('error')).message, 'Room has no available player seats');
console.log('PASS: host, guest, offer, answer, server-derived peer, repeated invites');
for (const ws of [guest2.socket,guest.socket,host.socket]) ws.close();
