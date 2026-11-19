// Manual, server-free WebRTC signalling. No STUN or TURN requests are made.
(() => {
  "use strict";
  // Flutter may rewrite hash routes, so retain the signalling fragment first.
  const initialLink = location.hash.startsWith("#p2p=") ? location.href : null;
  const peers = new Map();
  const responseChannel = typeof BroadcastChannel === "undefined"
      ? null : new BroadcastChannel("stone-banner-p2p-responses-v1");
  const responses = new Set();

  function signal(id, event, data = "") {
    const peer = peers.get(id);
    if (peer) peer.callback(event, data);
  }

  function attachChannel(id, channel) {
    const peer = peers.get(id);
    if (!peer) return;
    peer.channel = channel;
    channel.onopen = () => signal(id, "open");
    channel.onclose = () => signal(id, "close");
    channel.onerror = () => signal(id, "error", "Data channel error.");
    channel.onmessage = (event) => {
      if (typeof event.data === "string" && event.data.length <= 131072)
        signal(id, "message", event.data);
    };
  }

  function create(id, isHost, callback) {
    if (!window.RTCPeerConnection) throw Error("WebRTC is unavailable.");
    if (peers.has(id)) throw Error("Peer already exists.");
    const connection = new RTCPeerConnection({iceServers: []});
    peers.set(id, {connection, callback, channel: null});
    connection.ondatachannel = (event) => attachChannel(id, event.channel);
    connection.onconnectionstatechange = () => {
      const state = connection.connectionState;
      if (state === "failed") signal(id, "error", "Direct connection failed. Without STUN/TURN, some networks cannot connect.");
      if (state === "disconnected" || state === "closed") signal(id, "close");
    };
    if (isHost) attachChannel(id, connection.createDataChannel("stone-banner", {ordered: true}));
  }

  function waitForCandidates(connection) {
    if (connection.iceGatheringState === "complete") return Promise.resolve();
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        connection.removeEventListener("icegatheringstatechange", check);
        reject(Error("Collecting network candidates timed out. Try again."));
      }, 20000);
      function check() {
        if (connection.iceGatheringState === "complete") {
          clearTimeout(timer);
          connection.removeEventListener("icegatheringstatechange", check);
          resolve();
        }
      }
      connection.addEventListener("icegatheringstatechange", check);
      check();
    });
  }

  async function offer(id) {
    const connection = peers.get(id).connection;
    await connection.setLocalDescription(await connection.createOffer());
    await waitForCandidates(connection);
    return JSON.stringify(connection.localDescription);
  }
  async function answer(id, remote) {
    const connection = peers.get(id).connection;
    const description = JSON.parse(remote);
    if (description.type !== "offer") throw Error("Not a WebRTC offer.");
    await connection.setRemoteDescription(description);
    await connection.setLocalDescription(await connection.createAnswer());
    await waitForCandidates(connection);
    return JSON.stringify(connection.localDescription);
  }
  async function accept(id, remote) {
    const description = JSON.parse(remote);
    if (description.type !== "answer") throw Error("Not a WebRTC answer.");
    await peers.get(id).connection.setRemoteDescription(description);
  }

  window.stoneP2p = {
    initialLink() { return initialLink; },
    create, offer, answer, accept,
    send(id, message) {
      const channel = peers.get(id)?.channel;
      if (channel?.readyState !== "open") throw Error("Peer not connected.");
      channel.send(message);
    },
    close(id) {
      const peer = peers.get(id);
      if (!peer) return;
      peers.delete(id);
      peer.channel?.close();
      peer.connection.close();
    },
    onAnswer(callback) { responses.add(callback); },
    offAnswer(callback) { responses.delete(callback); },
    postAnswer(encoded) { responseChannel?.postMessage(encoded); },
  };
  responseChannel?.addEventListener("message", (event) => {
    if (typeof event.data === "string" && event.data.length < 30000)
      for (const callback of responses) callback(event.data);
  });
})();
