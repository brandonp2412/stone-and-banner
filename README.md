# Stone & Banner

Original offline-first strategy game for **Android, Linux and web**, built in **Flutter/Dart**.
The app provides a playable 3–4-seat pass-and-play match: 19 hexes, legal roads
and settlements, seeded dice, finite resources, Bandit, bank and accepted player
trades, 15-VP win condition, and portable deterministic event replay.
Town Developments, Knights, Invasion, three Strategy Card decks, standing
non-reserving trades and tactical out-of-turn reactions are implemented.

On Linux, use stock Flutter 3.47.6 and run `flutter run -d linux`. Flutter
3.50.0 has an NVIDIA/Wayland rendering regression on the tested desktop.
No project SDK, wrapper, or graphics environment overrides are required.

## Web

### Server-free WebRTC multiplayer (browser)

Open [Stone & Banner](https://brandonp2412.github.io/stone-and-banner/) and
choose **P2P multiplayer**. The host keeps their browser tab open, generates
one **invite link per guest**, and sends the links via any chat. Each guest
opens their invitation, chooses a unique name, then sends back a **response
link**. The host pastes each response link into their original host tab (or
opens it in a *new* tab to forward it automatically). When all 3–4 players
are connected, the host starts the match.

WebRTC DataChannels carry **only direct encrypted peer-to-peer game traffic**.
No signalling server, TURN relay, accounts, or remote match storage are used.
Public STUN servers operated by Google (stun.l.google.com:19302) and
Cloudflare (stun.cloudflare.com:3478) help the browsers discover publicly
reachable UDP endpoints and attempt NAT hole punching. STUN operators see
connection metadata including your public IP; game moves are **never** sent
to them. The host browser still performs game-state authority and transmits
a filtered view to each player. Do not close, refresh, or navigate away from
the host tab: the P2P session cannot be restored afterwards.

**WAN limitation:** STUN improves connectivity across home routers, but
carrier-grade NAT, symmetric NAT, and restrictive firewalls can still make
direct connections impossible. There is deliberately no TURN relay fallback
or other hosted multiplayer service. If a connection attempt fails, the host
can choose **Replace expired or unused invitations** and share new links,
or participants can try a different network or direct public IPv6. Local-LAN
play continues to work if STUN is unavailable.

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
