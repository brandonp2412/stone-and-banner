# Stone & Banner

Original offline-first Android strategy game built in **Flutter/Dart**.
The app provides a playable 3–4-seat pass-and-play match: 19 hexes, legal roads
and settlements, seeded dice, finite resources, Bandit, bank and accepted player
trades, 15-VP win condition, and portable deterministic event replay.
Town Developments, Knights, Invasion, three Strategy Card decks, standing
non-reserving trades and tactical out-of-turn reactions are implemented.

On Linux, use stock Flutter 3.47.6 and run `flutter run -d linux`. Flutter
3.50.0 has an NVIDIA/Wayland rendering regression on the tested desktop.
No project SDK, wrapper, or graphics environment overrides are required.
