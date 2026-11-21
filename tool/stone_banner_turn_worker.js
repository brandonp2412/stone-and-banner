// Public, free-tier-only credential broker. Set TURN_USER and TURN_PASS as
// Cloudflare Worker secrets. Metered Free stops relay service at its quota.
const WEB_ORIGIN = 'https://brandonp2412.github.io';
export default {
  async fetch(request, env) {
    const origin = request.headers.get('Origin');
    const headers = {
      'Content-Type': 'application/json; charset=utf-8',
      'Access-Control-Allow-Origin': WEB_ORIGIN,
      'Access-Control-Allow-Headers': 'Content-Type',
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      'Cache-Control': 'no-store, max-age=0',
      'X-Content-Type-Options': 'nosniff',
    };
    if (request.method === 'OPTIONS') {
      return new Response(null, {status: origin === WEB_ORIGIN ? 204 : 403, headers});
    }
    if (request.method !== 'GET' || new URL(request.url).pathname !== '/ice' ||
        (origin && origin !== WEB_ORIGIN)) {
      return new Response(JSON.stringify({error: 'Not found'}), {status: 404, headers});
    }
    if (!env.TURN_USER || !env.TURN_PASS) {
      return new Response(JSON.stringify({error: 'Relay not provisioned'}), {status: 503, headers});
    }
    const username = env.TURN_USER;
    const credential = env.TURN_PASS;
    return new Response(JSON.stringify({iceServers: [
      {urls: 'stun:stun.l.google.com:19302'},
      {urls: 'stun:stun.cloudflare.com:3478'},
      {urls: 'turn:global.relay.metered.ca:80', username, credential},
      {urls: 'turn:global.relay.metered.ca:80?transport=tcp', username, credential},
      {urls: 'turn:global.relay.metered.ca:443', username, credential},
      {urls: 'turns:global.relay.metered.ca:443?transport=tcp', username, credential},
    ]}), {headers});
  },
};
