// Static-hosted manual signalling. Direct ICE first, capped free TURN on restrictive NATs.
(() => {
  "use strict";
  // Flutter may rewrite hash routes, so retain the signalling fragment first.
  const initialLink = location.hash.startsWith("#p2p=") ? location.href : null;
  // Public STUN endpoints are used only for endpoint discovery, never for
  // relaying moves. Two independent operators improve availability.
  const directIceServers = [
    {urls: "stun:stun.l.google.com:19302"},
    {urls: "stun:stun.cloudflare.com:3478"},
  ];
  const relayConfigUrl = "https://stone-banner-turn.brandonp2412.workers.dev/ice";
  // The Worker holds the TURN secret; no credential is committed or baked into
  // the publicly hosted Flutter build. A short timeout preserves LAN play when
  // the free relay quota is exhausted or the Worker is unreachable.
  let relayConfigPromise;
  function relayConfig() {
    relayConfigPromise ??= (async () => {
      const abort = typeof AbortController === 'undefined' ? null : new AbortController();
      const timer = abort ? setTimeout(() => abort.abort(), 7000) : null;
      try {
        const response = await fetch(relayConfigUrl, {
          mode: "cors", cache: "no-store", ...(abort ? {signal: abort.signal} : {}),
        });
        if (!response.ok) throw Error(`Free relay unavailable (HTTP ${response.status})`);
        const payload = await response.json();
        if (!Array.isArray(payload.iceServers) ||
            !payload.iceServers.some(server => /^turns?:/.test(server.urls || "")))
          throw Error("Free relay supplied no TURN candidates");
        return payload.iceServers;
      } finally { clearTimeout(timer); }
    })().catch(error => { relayConfigPromise = undefined; throw error; });
    return relayConfigPromise;
  }
  const peers = new Map();
  const responseChannel = typeof BroadcastChannel === "undefined"
      ? null : new BroadcastChannel("stone-banner-p2p-responses-v1");
  const responses = new Set();
  const pendingForwards = new Map();
  let hosting = false;

  function validPrivateIPv4(value) {
    if (typeof value !== "string" || !/^\d{1,3}(\.\d{1,3}){3}$/.test(value)) return false;
    const a = value.split(".").map(Number);
    return a.every(n => n >= 0 && n <= 255) &&
      (a[0] === 10 || a[0] === 172 && a[1] >= 16 && a[1] <= 31 ||
       a[0] === 192 && a[1] === 168 || a[0] === 100 && a[1] >= 64 && a[1] <= 127);
  }

  function safeDescription(connection) {
    const description = connection.localDescription;
    if (!description?.sdp) return JSON.stringify(description);
    // Management VPN is solely for remote ADB access, never gameplay.
    const rows = description.sdp.split(/\r?\n/).filter(row =>
      !(row.startsWith("a=candidate:") && / 10\.66\.66\.\d+ /i.test(row)));
    return JSON.stringify({type: description.type, sdp: rows.join("\r\n")});
  }

  // Stop Flutter's hash router from consuming an answer as navigation, and
  // retry delivery until the Dart host confirms setRemoteDescription succeeded.
  window.addEventListener("hashchange", (event) => {
    if (!location.hash.startsWith("#p2p=")) return;
    const link = location.href;
    let type;
    try {
      const encoded = location.hash.substring("#p2p=".length);
      const base64 = encoded.replace(/-/g, "+").replace(/_/g, "/");
      type = JSON.parse(atob(base64))?.type;
      if (type !== "offer" && type !== "answer") return;
    } catch (_) {
      return;
    }
    event?.stopImmediatePropagation?.();
    if (!hosting) {
      // Opening a link into an already-open home/guest document is a same-page
      // navigation. Reload so initialLink captures it and Flutter opens P2P.
      location.reload();
      return;
    }
    // A host must never be replaced with a guest invitation.
    history.replaceState(history.state, "", location.pathname + location.search);
    if (type === "offer") return;
    const receiptId = crypto.randomUUID();
    let remaining = 5;
    const timer = setInterval(() => {
      if (!pendingForwards.has(receiptId) || remaining-- <= 0) {
        clearInterval(timer);
        pendingForwards.delete(receiptId);
        return;
      }
      for (const callback of responses) callback(link, receiptId);
    }, 750);
    pendingForwards.set(receiptId, () => {
      pendingForwards.delete(receiptId);
      clearInterval(timer);
    });
    for (const callback of responses) callback(link, receiptId);
  });

  window.addEventListener("beforeunload", (event) => {
    if (!hosting || peers.size === 0) return;
    // Browser may ignore this prompt (especially iOS), but when supported it
    // protects the in-memory WebRTC host from an accidental page replacement.
    event.preventDefault();
    event.returnValue = "";
  });

  // Cross-tab signalling uses an acknowledged same-origin BroadcastChannel.
  // It cannot reach separate browser profiles or in-app browser partitions.
  function forwardAnswer(link) {
    if (!responseChannel || typeof link !== "string" || link.length > 30000)
      return Promise.resolve(false);
    const id = crypto.randomUUID();
    return new Promise((resolve) => {
      let remaining = 60;
      const send = () => {
        if (--remaining < 0) {
          clearInterval(timer);
          pendingForwards.delete(id);
          resolve(false);
          return;
        }
        responseChannel.postMessage({kind: "answer", id, link});
      };
      const timer = setInterval(send, 1200);
      pendingForwards.set(id, (accepted) => {
        clearInterval(timer);
        pendingForwards.delete(id);
        resolve(accepted);
      });
      send();
    });
  }

  function acknowledgeAnswer(id, accepted) {
    // A response opened in the same tab must acknowledge locally; BroadcastChannel
    // never delivers messages to the object that originally posted them.
    pendingForwards.get(id)?.(!!accepted);
    if (responseChannel && id)
      responseChannel.postMessage({kind: "ack", id, accepted: !!accepted});
  }

  function signal(id, event, data = "") {
    const peer = peers.get(id);
    if (peer) peer.callback(event, data);
  }

  function attachChannel(id, channel) {
    const peer = peers.get(id);
    if (!peer) return;
    peer.channel = channel;
    channel.onopen = () => {
      clearTimeout(peer.failureTimer);
      peer.failureTimer = null;
      peer.everConnected = true;
      signal(id, "open");
      reportDirectPath(id);
    };
    channel.onclose = () => {
      clearTimeout(peer.disconnectTimer);
      peer.disconnectTimer = null;
      signal(id, "close");
    };
    channel.onerror = () => signal(id, "error", "Data channel error.");
    channel.onmessage = (event) => {
      if (typeof event.data === "string" && event.data.length <= 131072)
        signal(id, "message", event.data);
    };
  }

  function create(id, isHost, callback) {
    if (!window.RTCPeerConnection) throw Error("WebRTC is unavailable.");
    if (peers.has(id)) throw Error("Peer already exists.");
    const connection = new RTCPeerConnection({iceServers: directIceServers, iceTransportPolicy: "all"});
    const peer = {connection, callback, channel: null,
      relayConfigured: false, relayConfigError: null, failureTimer: null, disconnectTimer: null, everConnected: false};
    peer.configReady = relayConfig().then(servers => {
      if (peers.get(id) !== peer) return;
      connection.setConfiguration({iceServers: servers, iceTransportPolicy: "all"});
      peer.relayConfigured = true;
    }).catch(error => {
      peer.relayConfigError = String(error).slice(0, 160);
      signal(id, "diagnostic", `Free TURN relay unavailable; direct connections only: ${peer.relayConfigError}`);
    });
    peers.set(id, peer);
    connection.ondatachannel = (event) => attachChannel(id, event.channel);
    connection.onconnectionstatechange = () => {
      const state = connection.connectionState;
      if (state === "failed") {
        clearTimeout(peer.disconnectTimer);
        peer.disconnectTimer = null;
        if (peer.everConnected) {
          signal(id, "close");
          signal(id, "error", "WebRTC connection dropped during gameplay. Battery Saver, " +
            "background suspension or a network change can interrupt ICE. " +
            "Keep both apps in the foreground and copy diagnostics.");
        } else if (!isHost) {
          // The guest can fail preliminary ICE checks before the host has even
          // applied the answer link. Do not report that as a final NAT failure.
          peer.failureTimer ??= setTimeout(() => {
            peer.failureTimer = null;
            if (peers.get(id) !== peer || peer.channel?.readyState === "open") return;
            signal(id, "error", "Guest still cannot connect. Confirm the host " +
              "applied your response link, then copy diagnostics for ICE/relay details.");
          }, 45000);
        } else if (connection.remoteDescription) {
          signal(id, "error", "WebRTC ICE failed after the guest response was applied. " +
            "Copy diagnostics for local/remote candidates and relay availability.");
        }
      } else if (state === "connected") {
        peer.everConnected = true;
        clearTimeout(peer.failureTimer);
        peer.failureTimer = null;
        clearTimeout(peer.disconnectTimer);
        peer.disconnectTimer = null;
      }
      if (state === "disconnected") {
        peer.disconnectTimer ??= setTimeout(() => {
          peer.disconnectTimer = null;
          if (peers.get(id) === peer && connection.connectionState !== "connected")
            signal(id, "close");
        }, 30000);
      } else if (state === "closed") {
        clearTimeout(peer.disconnectTimer);
        peer.disconnectTimer = null;
        signal(id, "close");
      }
    };
    if (isHost) attachChannel(id, connection.createDataChannel("stone-banner", {ordered: true}));
  }

  // Manual (non-trickle) signalling requires candidates to be embedded in SDP.
  // Do not fail outright when external STUN is filtered: return the host/IPv6
  // candidates gathered so far so that same-LAN play still works.
  function peerRelayConfigured(connection) {
    for (const peer of peers.values()) {
      if (peer.connection === connection) return peer.relayConfigured;
    }
    return false;
  }

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
        // If TURN was provisioned, non-trickle invites must actually include
        // a relay candidate before returning. STUN alone fails on many mobile
        // carrier NATs even though a server-reflexive address was gathered.
        const hasRelay = event?.candidate?.type === "relay" ||
          / typ relay(?: |$)/m.test(connection.localDescription?.sdp || "");
        if ((hasRelay || (!peerRelayConfigured(connection) && foundPublic)) && !publicCandidateTimer)
          publicCandidateTimer = setTimeout(() => finish(false), 1000);
      };
      const timeout = setTimeout(() => finish(false), 12000);
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
    const summary = types.has("relay")
      ? "TURN relay candidate gathered; WAN connection available when direct paths fail."
      : hasPublic
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
      const usesPrivateRoute = [local, remote].every(candidate =>
        candidate.candidateType === "host" || candidate.candidateType === "prflx") &&
        [local, remote].some(candidate => validPrivateIPv4(candidate.address || candidate.ip));
      const internet = [local, remote].some(candidate =>
        candidate.candidateType === "srflx");
      signal(id, "path", [local, remote].some(candidate => candidate.candidateType === "relay")
        ? "Encrypted WebRTC via free TURN relay (WAN; not WireGuard)."
        : usesPrivateRoute
        ? "Direct encrypted P2P over a private LAN/VPN route (no relay)."
        : internet
          ? "Direct encrypted P2P via public NAT traversal (STUN-assisted)."
          : "Direct encrypted P2P connection established.");
    } catch (_) {
      signal(id, "path", "Encrypted WebRTC established; inspect ICE diagnostics for connection route.");
    }
  }

  async function offer(id) {
    await peers.get(id).configReady;
    const connection = peers.get(id).connection;
    await connection.setLocalDescription(await connection.createOffer());
    const complete = await waitForCandidates(connection);
    summarizeCandidates(id, complete);
    return safeDescription(connection);
  }
  async function answer(id, remote) {
    await peers.get(id).configReady;
    const connection = peers.get(id).connection;
    const description = JSON.parse(remote);
    if (description.type !== "offer") throw Error("Not a WebRTC offer.");
    await connection.setRemoteDescription(description);
    await connection.setLocalDescription(await connection.createAnswer());
    const complete = await waitForCandidates(connection);
    summarizeCandidates(id, complete);
    return safeDescription(connection);
  }
  async function accept(id, remote) {
    const description = JSON.parse(remote);
    if (description.type !== "answer") throw Error("Not a WebRTC answer.");
    await peers.get(id).connection.setRemoteDescription(description);
  }

  // Detailed, redacted connection diagnostics. Never include raw SDP, host IPs,
  // ICE passwords or certificate fingerprints in a report copied for support.
  function candidateDetails(description) {
    const rows = (description?.sdp || "").split(/\r?\n/);
    return rows.filter(row => row.startsWith("a=candidate:")).map(row => {
      const parts = row.split(/\s+/);
      const typeAt = parts.indexOf("typ");
      const address = parts[4] || "";
      return {
        type: typeAt >= 0 ? parts[typeAt + 1] : "unknown",
        protocol: (parts[2] || "").toLowerCase(),
        family: address.endsWith(".local") ? "mDNS" : address.includes(":") ? "IPv6" : "IPv4",
        mdns: address.endsWith(".local"),
        privateIPv4: validPrivateIPv4(address),
      };
    });
  }

  async function diagnostics(id) {
    const peer = peers.get(id);
    if (!peer) return JSON.stringify({status: "no active peer connection"});
    const connection = peer.connection;
    const result = {
      engine: "browser WebRTC",
      connectionState: connection.connectionState,
      iceConnectionState: connection.iceConnectionState,
      iceGatheringState: connection.iceGatheringState,
      signalingState: connection.signalingState,
      dataChannelState: peer.channel?.readyState || "not created",
      localDescription: connection.localDescription?.type || "none",
      remoteDescription: connection.remoteDescription?.type || "none",
      localCandidates: candidateDetails(connection.localDescription),
      remoteCandidates: candidateDetails(connection.remoteDescription),
      relayConfigured: peer.relayConfigured,
      relayConfigError: peer.relayConfigError,
      connectivityChecks: null,
      selectedPair: null,
    };
    try {
      const stats = await connection.getStats();
      const checks = {candidatePairs: 0, requestsSent: 0, responsesReceived: 0,
        requestsReceived: 0, succeededPairs: 0};
      stats.forEach(item => {
        if (item.type !== "candidate-pair") return;
        checks.candidatePairs++;
        checks.requestsSent += item.requestsSent || 0;
        checks.responsesReceived += item.responsesReceived || 0;
        checks.requestsReceived += item.requestsReceived || 0;
        if (item.state === "succeeded") checks.succeededPairs++;
      });
      result.connectivityChecks = checks;
      let pair;
      stats.forEach(item => {
        if (item.type === "transport" && item.selectedCandidatePairId) {
          pair = stats.get(item.selectedCandidatePairId);
        }
      });
      if (!pair) {
        stats.forEach(item => {
          if (item.type === "candidate-pair" && item.state === "succeeded" && item.nominated) pair = item;
        });
      }
      if (pair) {
        const local = stats.get(pair.localCandidateId);
        const remote = stats.get(pair.remoteCandidateId);
        result.selectedPair = {
          state: pair.state,
          nominated: !!pair.nominated,
          rttMs: typeof pair.currentRoundTripTime === "number"
            ? Math.round(pair.currentRoundTripTime * 1000) : null,
          localType: local?.candidateType || null,
          remoteType: remote?.candidateType || null,
          localProtocol: local?.protocol || null,
          remoteProtocol: remote?.protocol || null,
        };
      }
    } catch (error) {
      result.statsError = String(error).slice(0, 180);
    }
    return JSON.stringify(result);
  }

  window.stoneP2p = {
    initialLink() { return initialLink; },
    create, offer, answer, accept, diagnostics,
    send(id, message) {
      const channel = peers.get(id)?.channel;
      if (channel?.readyState !== "open") throw Error("Peer not connected.");
      channel.send(message);
    },
    close(id) {
      const peer = peers.get(id);
      if (!peer) return;
      peers.delete(id);
      clearTimeout(peer.failureTimer);
      clearTimeout(peer.disconnectTimer);
      peer.channel?.close();
      peer.connection.close();
    },
    onAnswer(callback) { responses.add(callback); },
    offAnswer(callback) { responses.delete(callback); },
    forwardAnswer,
    acknowledgeAnswer,
    setHosting(value) { hosting = !!value; },
  };
  responseChannel?.addEventListener("message", (event) => {
    const data = event.data;
    if (data?.kind === "ack" && typeof data.id === "string") {
      pendingForwards.get(data.id)?.(data.accepted === true);
    } else if (data?.kind === "answer" &&
               typeof data.link === "string" && data.link.length < 30000 &&
               typeof data.id === "string" && data.id.length < 150) {
      for (const callback of responses) callback(data.link, data.id);
    }
  });
})();
