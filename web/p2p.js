// Static-hosted manual signalling. Public STUN for direct UDP NAT traversal; no TURN or gameplay server.
(() => {
  "use strict";
  // Flutter may rewrite hash routes, so retain the signalling fragment first.
  const initialLink = location.hash.startsWith("#p2p=") ? location.href : null;
  // Public STUN endpoints are used only for endpoint discovery, never for
  // relaying moves. Two independent operators improve availability.
  const iceServers = [
    {urls: "stun:stun.l.google.com:19302"},
    {urls: "stun:stun.cloudflare.com:3478"},
  ];
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
    channel.onopen = () => {
      signal(id, "open");
      reportDirectPath(id);
    };
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
    const connection = new RTCPeerConnection({iceServers, iceTransportPolicy: "all"});
    peers.set(id, {connection, callback, channel: null});
    connection.ondatachannel = (event) => attachChannel(id, event.channel);
    connection.onconnectionstatechange = () => {
      const state = connection.connectionState;
      if (state === "failed")
        signal(id, "error", "Direct connection failed (NAT/firewall). No relay is configured. Try another network or reachable IPv6.");
      if (state === "disconnected" || state === "closed") signal(id, "close");
    };
    if (isHost) attachChannel(id, connection.createDataChannel("stone-banner", {ordered: true}));
  }

  // Manual (non-trickle) signalling requires candidates to be embedded in SDP.
  // Do not fail outright when external STUN is filtered: return the host/IPv6
  // candidates gathered so far so that same-LAN play still works.
  function waitForCandidates(connection) {
    if (connection.iceGatheringState === "complete") return Promise.resolve(true);
    return new Promise((resolve) => {
      let finished = false;
      let publicCandidateTimer;
      const finish = (complete) => {
        if (finished) return;
        finished = true;
        clearTimeout(timeout);
        clearTimeout(publicCandidateTimer);
        connection.removeEventListener("icegatheringstatechange", check);
        connection.removeEventListener("icecandidate", check);
        resolve(complete);
      };
      const check = (event) => {
        if (connection.iceGatheringState === "complete") return finish(true);
        const foundPublic = event?.candidate?.type === "srflx" ||
          / typ (srflx|prflx)/.test(connection.localDescription?.sdp || "");
        // A confirmed public endpoint is already enough for a non-trickle
        // invitation. Briefly collect additional candidates without making
        // everyone stare at a 12-second spinner.
        if (foundPublic && !publicCandidateTimer)
          publicCandidateTimer = setTimeout(() => finish(false), 1000);
      };
      const timeout = setTimeout(() => finish(false), 9000);
      connection.addEventListener("icegatheringstatechange", check);
      connection.addEventListener("icecandidate", check);
      check();
    });
  }

  function summarizeCandidates(id, complete) {
    const sdp = peers.get(id)?.connection.localDescription?.sdp || "";
    const candidates = sdp.split(/\r?\n/).filter(line => line.startsWith("a=candidate:"));
    const types = new Set(candidates.map(line => line.match(/ typ (host|srflx|prflx|relay)(?: |$)/)?.[1]).filter(Boolean));
    const hasPublic = types.has("srflx") || types.has("prflx");
    const summary = hasPublic
      ? "Public STUN candidate found; direct internet connection can be attempted."
      : types.has("host")
        ? "Only local candidates available; direct internet connection may fail."
        : "No network candidates found yet; check network connectivity.";
    signal(id, "diagnostic", summary +
      (complete ? "" : hasPublic ? " Using available public candidates now."
      : " Public discovery was unavailable; trying local candidates."));
  }

  async function reportDirectPath(id) {
    const peer = peers.get(id);
    if (!peer) return;
    try {
      const stats = await peer.connection.getStats();
      let selected;
      stats.forEach(item => {
        if (item.type === "transport" && item.selectedCandidatePairId)
          selected = stats.get(item.selectedCandidatePairId);
      });
      if (!selected) {
        stats.forEach(item => {
          if (item.type === "candidate-pair" && item.nominated && item.state === "succeeded") selected = item;
        });
      }
      const local = stats.get(selected?.localCandidateId);
      const remote = stats.get(selected?.remoteCandidateId);
      if (!local || !remote) return;
      // Do not expose or log IP addresses.
      const internet = [local.candidateType, remote.candidateType].some(
        type => type === "srflx" || type === "prflx");
      signal(id, "path", internet
        ? "Direct encrypted P2P via NAT traversal (STUN-assisted)."
        : "Direct encrypted P2P connection established.");
    } catch (_) {
      signal(id, "path", "Direct encrypted P2P connection established.");
    }
  }

  async function offer(id) {
    const connection = peers.get(id).connection;
    await connection.setLocalDescription(await connection.createOffer());
    const complete = await waitForCandidates(connection);
    summarizeCandidates(id, complete);
    return JSON.stringify(connection.localDescription);
  }
  async function answer(id, remote) {
    const connection = peers.get(id).connection;
    const description = JSON.parse(remote);
    if (description.type !== "offer") throw Error("Not a WebRTC offer.");
    await connection.setRemoteDescription(description);
    await connection.setLocalDescription(await connection.createAnswer());
    const complete = await waitForCandidates(connection);
    summarizeCandidates(id, complete);
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
