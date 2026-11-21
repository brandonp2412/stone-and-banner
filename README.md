# Stone & Banner

Offline-first strategy game for **Android, Linux and web**, built in **Flutter/Dart**.
The app provides a playable 3–4-seat pass-and-play match: 19 hexes, legal roads
and settlements, seeded dice, finite resources, Bandit, bank and accepted player
trades, 15-VP win condition, and portable deterministic event replay.
Town Developments, Knights, Invasion, three Strategy Card decks, standing
non-reserving trades and tactical out-of-turn reactions are implemented.

On Linux, use stock Flutter 3.47.6 and run `flutter run -d linux`. Flutter
3.50.0 has an NVIDIA/Wayland rendering regression on the tested desktop.
No project SDK, wrapper, or graphics environment overrides are required.

## Web

### Peer-to-peer WebRTC multiplayer (web, Android, Linux)

Open [Stone & Banner](https://brandonp2412.github.io/stone-and-banner/) and
choose **P2P multiplayer**. Host a room, then share the **same invitation
link** with each guest. They open it, enter a name, and tap **Join game**.
A small Cloudflare Durable Object exchanges WebRTC offers/answers automatically.
No response links, copied SDP, accounts, or persistent server-side games are
required. The host must keep the game running; refreshing closes the session.

When free signalling is unavailable, the lobby exposes the old manual
offer/answer pairing workflow. Manual invitations are still per-player;
guests must return their response links to the host.

Rooms support 3–4 seats with any combination of remote people and bots.
Computer players run the same local AI on the host, not in the Worker.
WebRTC DataChannels carry the encrypted multiplayer messages directly
between devices where NAT allows. On restrictive NATs, a separately provisioned
free capped TURN relay may forward encrypted WebRTC traffic. The existing
Cloudflare /ice Worker supplies those TURN credentials, while the separate
stone-banner-signal Durable Object only exchanges SDP during setup.
SDP can expose connection metadata to the signalling operator, but no
game state, gameplay moves or matches are stored by the signalling Worker.

To deploy signalling independently of the existing TURN Worker:
    npx wrangler deploy --config wrangler.signalling.jsonc

Deployment requires Cloudflare authentication and a Workers Free allocation.
For local testing, set STONE_SIGNAL_ENABLED=true and override STONE_SIGNAL_URL
with the local WebSocket URL. Public release builds now default to
STONE_SIGNAL_ENABLED=true. Debug builds default to false unless overridden. The default endpoint is
wss://stone-banner-signal.brandonp2412.workers.dev/signal/.
The old manual flow remains available when signalling is offline.

**Connection diagnostics:** If a one-link invite fails, use **Copy diagnostics**
on the error banner. Reports now record each signalling handshake attempt,
elapsed time, socket errors/close codes, and an independent HTTPS status probe
showing whether Cloudflare could find the host signalling socket. The probe
includes Cloudflare's request Ray ID when available. The report omits room
keys, SDP, peer IDs and full IP addresses. A host may remain online while its
signalling WebSocket is rejected; these are no longer treated as equivalent.
The Worker supports temporarily unavailable hosts, reconnection on resume,
and older host app builds that do not send host_ready.


Play online: https://brandonp2412.github.io/stone-and-banner/

The GitHub Actions workflow builds and publishes this site after each push to
`main`, and can also be run manually from GitHub Actions.


```sh
flutter pub get
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080
# Production static assets:
flutter build web --release
```

Serve `build/web/` over HTTP(S), or deploy its contents to any static web
host. Browser games autosave in that origin's local storage and restore on
refresh; changing the origin, clearing browser storage or using private mode
will not carry the saved game across. Share a replay before clearing storage.

LAN multiplayer uses an **existing private LAN WebSocket host**:

```sh
dart run tool/lan_server.dart --bind 0.0.0.0 --port 8765
```

In the browser use `ws://HOST_LAN_IP:8765/room` from an HTTP page. For
HTTPS deployments, browsers require a trusted `wss://` endpoint via a
self-hosted TLS reverse proxy; otherwise mixed-content restrictions block
connections. The browser cannot itself host the LAN server.
