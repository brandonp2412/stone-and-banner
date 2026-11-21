// Ephemeral WebRTC SDP exchange only. Game messages always use DataChannels.
// Deploy independently from the existing /ice credential broker. Durable
// Objects with SQLite backing work on Cloudflare Workers Free. No storage,
// accounts, TURN credentials, game state, or SDP logs are kept here.
const ALLOWED_ORIGIN = 'https://brandonp2412.github.io';
const MAX_MESSAGE = 20000;
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
    if (request.headers.get('Upgrade')?.toLowerCase() !== 'websocket' ||
        !match || !ROOM_KEY.test(match[1])) return fail('Not found', 404);
    // Browser origins are checked; native apps do not send an Origin header.
    const origin = request.headers.get('Origin');
    if (origin && origin !== ALLOWED_ORIGIN &&
        !/^http:\/\/(?:localhost|127\.0\.0\.1)(?::\d+)?$/.test(origin))
      return fail('Origin not allowed', 403);
    const role = url.searchParams.get('role');
    if (role !== 'host' && role !== 'guest') return fail('Invalid role');
    const instance = env.SIGNAL_ROOMS.get(env.SIGNAL_ROOMS.idFromName(match[1]));
    return instance.fetch(request);
  },
};

export class SignalRoom {
  constructor(state) { this.state = state; }

  async fetch(request) {
    const role = new URL(request.url).searchParams.get('role');
    const activeHosts = this.state.getWebSockets('host');
    if (role === 'host' && activeHosts.length) return fail('Host already connected', 409);
    if (role === 'guest' && !activeHosts.length) return fail('Host is offline', 404);
    if (role === 'guest' && this.state.getWebSockets('guest').length >= 3)
      return fail('Room full', 409);
    const pair = new WebSocketPair();
    const client = pair[0], server = pair[1];
    const peer = role === 'guest' ? crypto.randomUUID() : null;
    this.state.acceptWebSocket(server, [role]);
    server.serializeAttachment({role, peer});
    server.send(JSON.stringify({op: 'ready', ...(peer ? {peer} : {})}));
    if (peer) {
      for (const host of activeHosts) {
        host.send(JSON.stringify({op: 'join', peer}));
      }
    }
    return new Response(null, {status: 101, webSocket: client});
  }

  _host() { return this.state.getWebSockets('host')[0]; }

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
      this._send(this._host(), {op:'answer', peer:identity.peer, sdp:msg.sdp});
    }
  }

  webSocketClose(ws) { this._closed(ws); }
  webSocketError(ws) { this._closed(ws); }

  _closed(ws) {
    const identity = ws.deserializeAttachment();
    if (!identity) return;
    if (identity.role === 'host') {
      for (const guest of this.state.getWebSockets('guest')) {
        if (guest !== ws) {
          this._send(guest, {op:'error', message:'Host left the room'});
          try { guest.close(1000, 'Host left'); } catch (_) {}
        }
      }
    } else {
      this._send(this._host(), {op:'left', peer: identity.peer});
    }
  }
}
