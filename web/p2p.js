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
  const pendingForwards = new Map();
  let hosting = false;
  const directAddressKey = "stone-banner-p2p-direct-address";

  // The browser may hide a WireGuard/LAN interface behind mDNS or omit it
  // entirely. A user-supplied address advertises another route to the *same*
  // browser UDP socket; it never introduces a signalling or gameplay server.
  function validPrivateIPv4(value) {
    if (typeof value !== "string" || !/^\d{1,3}(\.\d{1,3}){3}$/.test(value))
      return false;
    const a = value.split(".").map(Number);
    if (a.some(n => n > 255) || a[3] === 0 || a[3] === 255) return false;
    return a[0] === 10 || (a[0] === 172 && a[1] >= 16 && a[1] <= 31) ||
      (a[0] === 192 && a[1] === 168) ||
      (a[0] === 100 && a[1] >= 64 && a[1] <= 127);
  }
  let directAddress = "";
  try {
    const saved = localStorage.getItem(directAddressKey);
    if (validPrivateIPv4(saved)) directAddress = saved;
  } catch (_) { /* Private browsing may disallow persistence. */ }

  function setDirectAddress(value) {
    const address = String(value).trim();
    if (address && !validPrivateIPv4(address))
      throw Error("Use a reachable private IPv4 address (e.g. 10.x or 192.168.x.x).");
    directAddress = address;
    try {
      if (address) localStorage.setItem(directAddressKey, address);
      else localStorage.removeItem(directAddressKey);
    } catch (_) { /* Still usable for the current tab. */ }
  }

  function descriptionWithDirectAddress(connection) {
    const description = connection.localDescription;
    if (!directAddress || !description?.sdp) return JSON.stringify(description);
    const rows = description.sdp.split(/\r\n/);
    const index = rows.findIndex(line => line.startsWith("a=candidate:") &&
      / 1 udp /i.test(line) && / typ host(?: |$)/.test(line));
    if (index < 0) return JSON.stringify(description);
    const parts = rows[index].split(" ");
    if (parts.length < 8) return JSON.stringify(description);
    if (parts[4] === directAddress) return JSON.stringify(description);
    // A distinct foundation makes this an additional, independently checked
    // address. Preserve the *real* UDP socket port and ICE credentials.
    parts[0] = "a=candidate:8717234";
    parts[3] = String(Math.min(Number(parts[3]) - 1, 2113937150));
    parts[4] = directAddress;
    rows.splice(index + 1, 0, parts.join(" "));
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

  // Cross-tab signalling uses an acknowledged same-origin BroadcastChannel.
  // It cannot reach separate browser profiles or in-app browser partitions.
  function forwardAnswer(link) {
    if (!responseChannel || typeof link !== "string" || link.length > 30000)
      return Promise.resolve(false);
    const id = crypto.randomUUID();
    return new Promise((resolve) => {
      let remaining = 5;
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
      if (state === "failed") {
        const message = isHost && !connection.remoteDescription
          ? "Host is awaiting the guest’s response link; this is not yet a network failure."
          : isHost
            ? "WebRTC ICE failed. This can be LAN mDNS discovery, a blocked UDP route, or an incomplete candidate list—not necessarily NAT. Copy diagnostics to investigate."
            : "WebRTC ICE failed. Ensure the host applied your response link. If both are on Wi-Fi, mDNS/UDP discovery may be blocked. Copy diagnostics to investigate.";
        signal(id, "error", message);
      }
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
      const usesPrivateRoute = [local, remote].every(candidate =>
        candidate.candidateType === "host" || candidate.candidateType === "prflx") &&
        [local, remote].some(candidate => validPrivateIPv4(candidate.address || candidate.ip));
      const internet = [local, remote].some(candidate =>
        candidate.candidateType === "srflx");
      signal(id, "path", usesPrivateRoute
        ? "Direct encrypted P2P over a private LAN/VPN route (no relay)."
        : internet
          ? "Direct encrypted P2P via public NAT traversal (STUN-assisted)."
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
    return descriptionWithDirectAddress(connection);
  }
  // Some mobile networks map the same outbound UDP socket to *different*
  // public ports for each STUN destination. On such networks, a standard
  // server-reflexive offer may be unreachable from the peer even though a
  // nearby UDP mapping succeeds. This is a bounded, lower-priority, direct-
  // only ICE fallback; it never routes game traffic through a relay or VPN.
  // Activate only when two STUN observations prove endpoint-dependent port
  // mapping. In particular, never modify normal same-LAN offers.
  function endpointDependentCandidateOffer(description) {
    if (description?.type !== "offer" || typeof description.sdp !== "string")
      return {description, count: 0};
    const rows = description.sdp.split(/\r?\n/);
    const candidates = rows.filter(row => row.startsWith("a=candidate:"));
    const srflx = candidates.map(row => ({parts: row.split(/\s+/)}))
      .filter(({parts}) => {
        const marker = parts.indexOf("typ");
        return parts.length >= 8 && parts[2].toLowerCase() === "udp" &&
          marker >= 0 && parts[marker + 1] === "srflx" &&
          parts.indexOf("raddr") >= 0 && parts.indexOf("rport") >= 0;
      });
    // Multiple observations for one socket, with incompatible public ports,
    // are required. Avoid guessing on independent interfaces/sockets.
    const groups = new Map();
    for (const {parts} of srflx) {
      const address = parts[4];
      const port = Number(parts[5]);
      const raddr = parts[parts.indexOf("raddr") + 1];
      const rport = parts[parts.indexOf("rport") + 1];
      if (!/^\d{1,3}(?:\.\d{1,3}){3}$/.test(address) ||
          validPrivateIPv4(address) || address.startsWith("127.") ||
          !Number.isInteger(port) || port < 1024 || port > 65535)
        continue;
      const key = [parts[1], address, raddr, rport].join("|");
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(parts);
    }
    // Use the strongest sign of symmetric NAT; constrain the number and
    // range of checks to avoid a large SDP/UDP flood.
    const group = [...groups.values()].find(values =>
      new Set(values.map(parts => parts[5])).size >= 2);
    if (!group) return {description, count: 0};
    const first = group[0];
    const observed = new Set(group.map(parts => Number(parts[5])));
    const ports = new Set();
    for (let delta = 1; delta <= 96 && ports.size < 280; delta++) {
      for (const port of observed) {
        if (port - delta > 1024 && !observed.has(port - delta))
          ports.add(port - delta);
        if (port + delta <= 65535 && !observed.has(port + delta))
          ports.add(port + delta);
        if (ports.size >= 280) break;
      }
    }
    const extras = [];
    for (const port of ports) {
      const parts = [...first];
      parts[0] = "a=candidate:" + String(940000000 + port);
      parts[3] = "1677729500";
      parts[5] = String(port);
      extras.push(parts.join(" "));
    }
    if (!extras.length) return {description, count: 0};
    const end = rows.findIndex(row => row.startsWith("a=end-of-candidates"));
    if (end >= 0) rows.splice(end, 0, ...extras);
    else {
      const last = rows.findLastIndex(row => row.startsWith("a=candidate:"));
      rows.splice(last + 1, 0, ...extras);
    }
    return {description: {type: description.type, sdp: rows.join("\r\n")},
      count: extras.length};
  }

  async function answer(id, remote) {
    const connection = peers.get(id).connection;
    const description = JSON.parse(remote);
    if (description.type !== "offer") throw Error("Not a WebRTC offer.");
    const probed = endpointDependentCandidateOffer(description);
    if (probed.count > 0)
      signal(id, "diagnostic", `Endpoint-dependent carrier NAT detected: testing ${probed.count} nearby direct UDP port mappings (no relay).`);
    await connection.setRemoteDescription(probed.description);
    await connection.setLocalDescription(await connection.createAnswer());
    const complete = await waitForCandidates(connection);
    summarizeCandidates(id, complete);
    return descriptionWithDirectAddress(connection);
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
      privateAddressHintConfigured: !!directAddress,
      selectedPair: null,
    };
    try {
      const stats = await connection.getStats();
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
      peer.channel?.close();
      peer.connection.close();
    },
    onAnswer(callback) { responses.add(callback); },
    offAnswer(callback) { responses.delete(callback); },
    forwardAnswer,
    acknowledgeAnswer,
    setHosting(value) { hosting = !!value; },
    directAddress() { return directAddress; },
    setDirectAddress,
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
