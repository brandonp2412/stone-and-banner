# Reading persisted Linux matches during development

The native Linux app saves Flutter SharedPreferences in:

`~/.local/share/nz.stone_and_banner/shared_preferences.json`

Use the real persisted match when investigating a user's game. Read a copy;
do not overwrite the live preferences or start a new match to diagnose it.
The previous production app ID was `nz.presley.stone_and_banner`; its save
remains in `~/.local/share/nz.presley.stone_and_banner/`. When investigating a
match saved before the rename, check that location too. Renaming the app does
not move existing saves.
Other app IDs have separate saves (for example,
`nz.presley.stoneandbanner.isolatedqa` and the older
`com.example.stone_and_banner`). Check the player names and event count to
confirm you have the correct match.

The preferences JSON contains JSON-encoded strings:

- `flutter.stone_banner_local_session_v2`: decode this string to get a session
  with `version`, `replay` (another JSON string), and `computerSeats`.
- `flutter.stone_banner_local_replay_v1`: a standalone replay JSON string.
  The app prefers the session replay when restoring; use the standalone key
  as a fallback.

Extract a replay without modifying the save:

```sh
python3 - <<'PY'
import json
from pathlib import Path

path = Path.home() / '.local/share/nz.stone_and_banner/shared_preferences.json'
prefs = json.loads(path.read_text())
session_raw = prefs.get('flutter.stone_banner_local_session_v2')
session = json.loads(session_raw) if session_raw else {}
replay_raw = session.get('replay') or prefs['flutter.stone_banner_local_replay_v1']
replay = json.loads(replay_raw)
out = Path('/tmp/stone-and-banner-saved-replay.json')
out.write_text(replay_raw)
print(out)
print('Players:', replay['names'])
print('Events:', len(replay['events']))
print('Computer seats:', session.get('computerSeats'))
PY
```

From the repository root, audit with:

```sh
dart run tool/verify_replay.dart /tmp/stone-and-banner-saved-replay.json
```

If the `dart` wrapper reports no project or global executable, this machine's
SDK is available directly:

```sh
/home/brandon/.local/opt/flutter/bin/cache/dart-sdk/bin/dart --packages=.dart_tool/package_config.json tool/verify_replay.dart /tmp/stone-and-banner-saved-replay.json
```

Replays contain the seed, board seed, balance, player names, and accepted events,
not a serialized current board. Reconstruct state using
`MatchEngine.importReplay(replayRaw)` from
`package:stone_and_banner/engine/match.dart`. To inspect a past event, decode a
copy of the replay, replace `events` with `events.take(eventIndex).toList()`,
encode it, and import it. This reconstructs the state immediately before the
zero-based event at `eventIndex`; take `eventIndex + 1` for the state after it.
Temporary Dart scripts outside the repo can use the same explicit SDK and
`--packages=.dart_tool/package_config.json` command from the repository root.

For invasion investigations, inspect the state before the `invasion` event:
`MatchEngine.defenceStrength(state)`, `state.invasionAid`,
`MatchEngine.invasionStrength(state)`, and each guard's owner, rank, and active
flag. Inspect preceding `tactical` events for the players and goods pledged as
aid. After resolution, `state.lastInvasion` records the result, but guards
have been deactivated and emergency aid reset, so the current defence meter
cannot explain the previous result by itself.
