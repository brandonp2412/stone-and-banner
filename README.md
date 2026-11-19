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
