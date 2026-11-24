// Ephemeral WebRTC SDP exchange only. Game messages always use DataChannels.
// Deploy independently from the existing /ice credential broker. Durable
// Objects with SQLite backing work on Cloudflare Workers Free. No storage,
// accounts, TURN credentials, game state, or SDP logs are kept here.
const ALLOWED_ORIGIN = 'https://brandonp2412.github.io';
const MAX_MESSAGE = 20000;
const SIGNAL_PROTOCOL = 2;
const ROOM_KEY = /^[a-f0-9]{32}$/;

function fail(message, status = 400) {
  return new Response(JSON.stringify({error: message}), {
    status, headers: {'Content-Type': 'application/json', 'Cache-Control': 'no-store'},
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const match = /^\/signal\/([a-f0-9]{32})$/.exec(url.pathname);
    const status = /^\/signal\/status\/([a-f0-9]{32})$/.exec(url.pathname);
    if ((!match && !status) || !ROOM_KEY.test((match || status)[1]))
      return fail('Not found', 404);
    // Browsers must be able to probe the Worker after an opaque WebSocket
    // handshake failure. No room keys, SDP or addresses appear in diagnostics.
    const origin = request.headers.get('Origin');
    const allowed = !origin || origin === ALLOWED_ORIGIN ||
      /^http:\/\/(?:localhost|127\.0\.0\.1)(?::\d+)?$/.test(origin);
    const cors = {
      'Access-Control-Allow-Origin': allowed ? (origin || '*') : 'null',
      'Access-Control-Expose-Headers': 'CF-Ray',
      'Cache-Control': 'no-store',
    };
    if (status) {
      if (!allowed) return fail('Origin not allowed', 403);
      if (request.method !== 'GET') return fail('Method not allowed', 405);
      const instance = env.SIGNAL_ROOMS.get(env.SIGNAL_ROOMS.idFromName(status[1]));
      const response = await instance.fetch(request);
      return new Response(response.body, {
        status: response.status, headers: {...cors, 'Content-Type': 'application/json'},
      });
    }
    if (!allowed) return fail('Origin not allowed', 403);
    if (request.headers.get('Upgrade')?.toLowerCase() !== 'websocket')
      return fail('Expected websocket', 426);
    const role = url.searchParams.get('role');
    if (role !== 'host' && role !== 'guest') return fail('Invalid role');
    const instance = env.SIGNAL_ROOMS.get(env.SIGNAL_ROOMS.idFromName(match[1]));
    return instance.fetch(request);
  },
};

export class SignalRoom {
  constructor(state) { this.state = state; }

  async fetch(request) {
    if (request.method === 'GET' &&
        new URL(request.url).pathname.includes('/signal/status/')) {
      const hosts = this.state.getWebSockets('host');
      const guestCount = this.state.getWebSockets('guest').length;
      const hostReady = hosts.some(h => h.deserializeAttachment()?.ready === true);
      return new Response(JSON.stringify({
        protocol: SIGNAL_PROTOCOL,
        state: hostReady ? 'host_ready' : hosts.length ? 'host_connecting' : 'host_absent',
        hostSocketCount: hosts.length,
        pendingGuests: guestCount,
        serverTimeUtc: new Date().toISOString(),
      }), {headers: {'Content-Type': 'application/json', 'Cache-Control': 'no-store'}});
    }
    const role = new URL(request.url).searchParams.get('role');
    const activeHosts = this.state.getWebSockets('host');
    const guestCount = this.state.getWebSockets('guest').length;
    // Upgrade first: browsers hide 404/409 WebSocket bodies.
    const rejection = role === 'host' && activeHosts.length
      ? {code: 'host_busy', message: 'This host is already connected.'}
      : role === 'guest' && guestCount >= 5
      ? {code: 'room_full', message: 'This room has reached its guest limit.'}
      : null;
    const pair = new WebSocketPair();
    const client = pair[0], server = pair[1];
    const peer = role === 'guest' ? crypto.randomUUID() : null;
    this.state.acceptWebSocket(server, [rejection ? 'rejected' : role]);
    server.serializeAttachment({
      role: rejection ? 'rejected' : role, peer,
      ...(role === 'host' && !rejection ? {ready: false} : {}),
    });
    if (role === 'host' && !rejection) {
      // Older Android/web builds do not send host_ready. Give modern clients
      // time to initialize and then allow legacy hosts to receive guests.
      setTimeout(() => {
        try {
          const state = server.deserializeAttachment();
          if (state?.role === 'host' && !state.ready) {
            server.serializeAttachment({...state, ready: true, legacyReady: true});
            this._announceHost(server);
          }
        } catch (_) { /* Legacy host disconnected during grace period */ }
      }, 1500);
    }
    if (rejection) {
      server.send(JSON.stringify({op: 'error', ...rejection}));
      server.close(1000, 'Join rejected');
      return new Response(null, {status: 101, webSocket: client});
    }
    server.send(JSON.stringify({op: 'ready', protocol: SIGNAL_PROTOCOL, ...(peer ? {peer} : {})}));
    if (role === 'guest') {
      const readyHosts = activeHosts.filter(h => h.deserializeAttachment()?.ready);
      if (!readyHosts.length) {
        this._send(server, {op: 'waiting', code: 'host_offline',
          message: 'Waiting for the host to reopen this room…'});
      } else {
        for (const host of readyHosts) this._send(host, {op: 'join', peer});
      }
    }
    return new Response(null, {status: 101, webSocket: client});
  }

  _host() { return this.state.getWebSockets('host')[0]; }

  _announceHost(host) {
    for (const guest of this.state.getWebSockets('guest')) {
      const attachment = guest.deserializeAttachment();
      if (attachment?.peer && !attachment.paired) {
        this._send(guest, {op: 'host_online'});
        this._send(host, {op: 'join', peer: attachment.peer});
      }
    }
  }

  _guest(peer) {
    return this.state.getWebSockets('guest')
      .find(ws => ws.deserializeAttachment()?.peer === peer);
  }

  _send(ws, message) {
    if (ws) {
      try { ws.send(JSON.stringify(message)); } catch (_) { /* disconnected */ }
    }
  }

  webSocketMessage(ws, data) {
    if (typeof data !== 'string' || data.length > MAX_MESSAGE) {
      this._send(ws, {op:'error', message:'Signalling payload too large'});
      return;
    }
    let msg;
    try { msg = JSON.parse(data); } catch (_) { return; }
    const identity = ws.deserializeAttachment();
    if (!identity) return;
    if (msg.op === 'ping') {
      this._send(ws, {op: 'pong'});
      return;
    }
    if (identity.role === 'host' && msg.op === 'host_ready') {
      ws.serializeAttachment({...identity, ready: true});
      // Do not dispatch pending guests until the host has installed callbacks.
      this._announceHost(ws);
      return;
    }
    if (identity.role === 'host') {
      if (!['offer', 'reject'].includes(msg.op) || typeof msg.peer !== 'string') return;
      if (msg.op === 'offer' &&
          (typeof msg.sdp !== 'string' || msg.sdp.length > 18000 ||
           typeof msg.room !== 'string' || !/^[a-fA-F0-9]{8}$/.test(msg.room))) return;
      this._send(this._guest(msg.peer),
        msg.op === 'offer' ? {op:'offer', peer:msg.peer, room:msg.room, sdp:msg.sdp}
                           : {op:'error', message:'Room has no available player seats'});
    } else if (identity.role === 'guest' && msg.op === 'answer' &&
               typeof msg.sdp === 'string' && msg.sdp.length <= 18000) {
      // Peer identity comes from the socket attachment, not a client claim.
      ws.serializeAttachment({...identity, paired: true});
      this._send(this._host(), {op:'answer', peer:identity.peer, sdp:msg.sdp});
    }
  }

  webSocketClose(ws) { this._closed(ws); }
  webSocketError(ws) { this._closed(ws); }

  _closed(ws) {
    const identity = ws.deserializeAttachment();
    if (!identity) return;
    if (identity.role === 'host') {
      // Keep pending guest connections alive while the host reconnects.
      for (const guest of this.state.getWebSockets('guest')) {
        this._send(guest, {op: 'waiting', code: 'host_offline',
          message: 'Host disconnected. Waiting for reconnection…'});
      }
    } else if (identity.role === 'guest') {
      this._send(this._host(), {op: 'left', peer: identity.peer});
    }
  }
}
