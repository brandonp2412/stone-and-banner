import 'dart:async';

import 'compact_layout.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/lan_client.dart';
import '../network/lan_host.dart';
import '../engine/world_seed.dart';
import 'match_screen.dart';

class LanRoomPage extends StatefulWidget {
  const LanRoomPage({super.key});

  @override
  State<LanRoomPage> createState() => _LanRoomPageState();
}

class _LanRoomPageState extends State<LanRoomPage> {
  late final LanRoomClient client;
  final address = TextEditingController();
  final name = TextEditingController(text: 'Player');
  final roomCode = TextEditingController();
  String? savedRoom, savedToken;
  bool _edited = false;
  bool _restoring = false;
  Future<void> _settingsTail = Future<void>.value();
  bool host = !kIsWeb;
  int seats = 3;
  LanHostServer? _localHost;
  bool _starting = false, _searching = false;
  String? _inviteIp;
  List<String> _localAddresses = [];
  List<LanFoundRoom> _nearby = [];

  @override
  void initState() {
    super.initState();
    client = LanRoomClient(
      onSession: (url, room, token) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('lanUrl', url);
        await prefs.setString('lanRoom', room);
        await prefs.setString('lanToken', token);
        if (mounted) {
          setState(() {
            savedRoom = room;
            savedToken = token;
          });
        }
      },
    )..addListener(_refresh);
    for (final field in [address, name, roomCode]) {
      field.addListener(_saveSettings);
    }
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      if (!_edited) {
        _restoring = true;
        address.text = prefs.getString('lanJoinAddress') ?? address.text;
        name.text = prefs.getString('lanPlayerName') ?? name.text;
        roomCode.text = prefs.getString('lanJoinCode') ?? roomCode.text;
        host = kIsWeb ? false : (prefs.getBool('lanHost') ?? host);
        final count = prefs.getInt('lanSeats');
        if (count != null && count >= 3 && count <= 6) seats = count;
        _restoring = false;
      }
      savedRoom = prefs.getString('lanRoom');
      savedToken = prefs.getString('lanToken');
    });
    if (!host) unawaited(_discover());
  }

  void _saveSettings() {
    if (_restoring) return;
    _edited = true;
    final url = address.text;
    final playerName = name.text;
    final code = roomCode.text;
    final hosting = host;
    final count = seats;
    _settingsTail = _settingsTail.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('lanJoinAddress', url);
        await prefs.setString('lanPlayerName', playerName);
        await prefs.setString('lanJoinCode', code);
        await prefs.setBool('lanHost', hosting);
        await prefs.setInt('lanSeats', count);
      } on Object {
        if (mounted) {
          setState(() => client.error = 'Could not save LAN settings.');
        }
      }
    });
  }

  Future<void> _forget() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('lanRoom');
    await prefs.remove('lanToken');
    if (mounted) {
      setState(() {
        savedRoom = null;
        savedToken = null;
      });
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _discover() async {
    if (_searching) return;
    setState(() => _searching = true);
    try {
      final rooms = await LanHostServer.discover();
      if (mounted) setState(() => _nearby = rooms);
    } on Object {
      // Broadcast discovery is optional: direct invitations still work.
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  /// Invite format: 192.168.1.10:12345/ABCD1234. No WebSocket syntax.
  (String, String) _joinDetails() {
    var raw = address.text.trim();
    final secure = raw.startsWith('wss://') || raw.startsWith('https://');
    if (raw.startsWith('ws://')) raw = raw.substring(5);
    if (raw.startsWith('wss://')) raw = raw.substring(6);
    if (raw.startsWith('http://')) raw = raw.substring(7);
    if (raw.startsWith('https://')) raw = raw.substring(8);
    final parts = raw.split('/');
    final hostAddress = parts.first.trim();
    if (hostAddress.isEmpty) {
      throw const FormatException(
        'Enter a host address or select a nearby room.',
      );
    }
    final uri = Uri.tryParse('ws://$hostAddress');
    if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('Invalid LAN host address.');
    }
    final port = uri.hasPort ? uri.port : (secure ? 443 : 8765);
    if (port < 1 || port > 65535) {
      throw const FormatException('Invalid LAN port.');
    }
    final inviteCode = parts.length >= 2 && parts[1] != 'room'
        ? parts[1].trim()
        : '';
    final code = (inviteCode.isNotEmpty ? inviteCode : roomCode.text)
        .trim()
        .toUpperCase();
    if (code.isEmpty) throw const FormatException('Enter the room code.');
    return ('${secure ? 'wss' : 'ws'}://${uri.host}:$port/room', code);
  }

  Future<void> _createOrJoin() async {
    if (_starting) return;
    setState(() {
      _starting = true;
      client.error = null;
    });
    try {
      if (host) {
        final server = await LanHostServer.start();
        if (!mounted) {
          await server.close();
          return;
        }
        _localHost = server;
        final ips = await LanHostServer.localAddresses();
        if (!mounted) return;
        setState(() {
          _localAddresses = ips;
          _inviteIp = ips.isEmpty ? null : ips.first;
        });
        client.host(
          'ws://127.0.0.1:${server.port}/room',
          name.text,
          seats,
          randomWorldSeed(),
        );
      } else {
        final (url, code) = _joinDetails();
        client.join(url, name.text, code);
      }
    } on Object catch (error) {
      await _localHost?.close();
      _localHost = null;
      if (mounted) {
        setState(
          () => client.error = error is FormatException
              ? error.message
              : 'Could not host this game: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  String? get _invite {
    final ip = _inviteIp;
    if (ip == null || client.room == null || _localHost == null) return null;
    return '$ip:${_localHost!.port}/${client.room}';
  }

  @override
  void dispose() {
    client.removeListener(_refresh);
    client.dispose();
    _localHost?.close();
    address.dispose();
    name.dispose();
    roomCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = client.game;
    final seat = client.seat;
    final activeSeat = state?.actingSeat;
    final canAct =
        client.connected &&
        !client.pending &&
        state != null &&
        seat == activeSeat;
    final canReplyToTrade =
        client.connected &&
        !client.pending &&
        state != null &&
        seat != null &&
        state.offers.any(
          (offer) => offer.proposer == state.active && offer.canRespond(seat),
        );
    final wait = !client.connected
        ? 'Reconnecting to LAN host…'
        : client.pending
        ? 'Waiting for the host to confirm your move…'
        : state?.tactical != null
        ? 'Waiting for tactical response from ${state!.players[activeSeat!].id}…'
        : state != null
        ? 'Waiting for ${state.players[activeSeat!].id}…'
        : 'Waiting for players…';
    return Scaffold(
      appBar: state == null && MediaQuery.sizeOf(context).width >= 900
          ? AppBar(title: const Text('LAN multiplayer'))
          : null,
      body: Column(
        children: [
          if (client.error != null)
            MaterialBanner(
              content: Text(client.error!),
              actions: [
                TextButton(
                  onPressed: () => setState(() => client.error = null),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          if (client.room == null || seat == null)
            Expanded(child: _setup())
          else if (state == null)
            Expanded(child: _lobby())
          else
            Expanded(
              child: Stack(
                children: [
                  MatchView(
                    key: ValueKey(client.generation),
                    state: state,
                    onPlayAgain: seat == 0 && client.connected
                        ? client.playAgain
                        : null,
                    online: true,
                    onlineView: client.view,
                    viewingSeat: seat,
                    computerSeats: client.botSeats.toSet(),
                    onlineTurnSeconds: client.turnSecondsRemaining,
                    observing: !canAct,
                    tradeReplyAllowed: canReplyToTrade,
                    waitingMessage: canAct ? null : wait,
                    onEvent: client.dispatch,
                    onLeaveRoom: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _setup() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 550),
      child: ListView(
        padding: EdgeInsets.all(isCompactLandscape(context) ? 8 : 20),
        children: [
          if (MediaQuery.sizeOf(context).width < 900)
            Align(
              alignment: Alignment.centerLeft,
              child: isCompactLandscape(context)
                  ? SizedBox(
                      height: 36,
                      child: IconButton(
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                        padding: EdgeInsets.zero,
                      ),
                    )
                  : TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Back'),
                    ),
            ),
          Text(
            'Play together on Wi-Fi',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          if (!isCompactLandscape(context))
            const Text(
              'Native LAN rooms only: Android and Linux apps can join. '
              'For an iPhone, iPad, or web browser, return to Multiplayer '
              'and host a WebRTC game instead.',
            ),
          if (kIsWeb) ...[
            const SizedBox(height: 8),
            const Text(
              'To host, use the Android or Linux app. On an HTTPS website, joining LAN requires a trusted wss:// host; use P2P multiplayer for browser-to-browser play.',
            ),
          ],
          const SizedBox(height: 16),
          if (!kIsWeb)
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.wifi_tethering),
                  label: Text('Host game'),
                ),
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.wifi_find),
                  label: Text('Join game'),
                ),
              ],
              selected: {host},
              onSelectionChanged: (value) {
                setState(() => host = value.first);
                _saveSettings();
                if (!host) _discover();
              },
            ),
          const SizedBox(height: 14),
          TextField(
            controller: name,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Your player name',
            ),
          ),
          const SizedBox(height: 14),
          if (host) ...[
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final count in [3, 4, 5, 6])
                  ChoiceChip(
                    label: Text('$count players'),
                    selected: seats == count,
                    onSelected: (_) {
                      setState(() => seats = count);
                      _saveSettings();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Your device will host the game automatically. Keep it open while playing.',
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Nearby LAN games',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: _searching ? null : _discover,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Find LAN games',
                ),
              ],
            ),
            if (_searching) const LinearProgressIndicator(),
            for (final room in _nearby)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.wifi),
                  title: Text('Room ${room.code}'),
                  subtitle: Text(
                    '${room.players} of ${room.capacity} players · ${room.address}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    address.text = room.invite;
                    _createOrJoin();
                  },
                ),
              ),
            if (_nearby.isEmpty && !_searching)
              const Text(
                'No games found automatically? Paste the invite from your host.',
              ),
            const SizedBox(height: 14),
            TextField(
              controller: address,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Host invite or IP address',
                hintText: '192.168.1.10:12345/ABCD1234',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: roomCode,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Room code (if not included in invite)',
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: client.connecting || _starting ? null : _createOrJoin,
            icon: Icon(host ? Icons.wifi_tethering : Icons.login),
            label: Text(
              _starting || client.connecting
                  ? 'Connecting…'
                  : host
                  ? 'Host LAN game'
                  : 'Join LAN game',
            ),
          ),
          if (!host && savedRoom != null && savedToken != null) ...[
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: client.connecting
                  ? null
                  : () {
                      try {
                        final (url, _) = _joinDetails();
                        client.resume(url, savedRoom!, savedToken!);
                      } on Object catch (e) {
                        setState(() => client.error = '$e');
                      }
                    },
              icon: const Icon(Icons.restore),
              label: Text('Reconnect to $savedRoom'),
            ),
            TextButton(
              onPressed: _forget,
              child: const Text('Forget saved room credentials'),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _lobby() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 550),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (MediaQuery.sizeOf(context).width < 900)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back'),
              ),
            ),
          Text(
            'Room ${client.room}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Seat ${client.seat! + 1} of ${client.capacity} · '
            '${client.connected ? "Connected" : "Reconnecting…"}',
          ),
          const SizedBox(height: 12),
          if (_invite != null) ...[
            SelectableText(
              'Join using: $_invite',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_localAddresses.length > 1)
              DropdownButton<String>(
                value: _inviteIp,
                isExpanded: true,
                items: [
                  for (final ip in _localAddresses)
                    DropdownMenuItem(
                      value: ip,
                      child: Text('Network address: $ip'),
                    ),
                ],
                onChanged: (ip) => setState(() => _inviteIp = ip),
              ),
          ],
          OutlinedButton.icon(
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: _invite ?? client.room!)),
            icon: const Icon(Icons.copy),
            label: Text(
              _invite == null ? 'Copy room code' : 'Copy join invite',
            ),
          ),
          if (_localHost != null && _invite == null)
            const Text(
              'Could not identify this device’s LAN IP. Find its Wi-Fi IP in system settings.',
            ),
          const SizedBox(height: 16),
          if (client.seat == 0 && !client.started) ...[
            Row(
              children: [
                const Expanded(child: Text('Computer players')),
                DropdownButton<int>(
                  value: client.botCount.clamp(
                    0,
                    client.capacity - client.players.length,
                  ),
                  items: [
                    for (
                      var i = 0;
                      i <= client.capacity - client.players.length;
                      i++
                    )
                      DropdownMenuItem(value: i, child: Text('$i')),
                  ],
                  onChanged: client.connected
                      ? (count) {
                          if (count != null) client.setBots(count);
                        }
                      : null,
                ),
              ],
            ),
          ],
          for (var i = 0; i < client.capacity; i++)
            ListTile(
              leading: Icon(
                client.botSeats.contains(i) ||
                        (i >= client.players.length &&
                            i < client.players.length + client.botCount)
                    ? Icons.smart_toy_outlined
                    : i < client.connectedPlayers.length &&
                          client.connectedPlayers[i]
                    ? Icons.wifi
                    : Icons.wifi_off,
              ),
              title: Text(
                i < client.players.length
                    ? client.players[i]
                    : i < client.players.length + client.botCount
                    ? 'Computer ${i + 1}'
                    : 'Waiting for player…',
              ),
              subtitle: Text(i == 0 ? 'Room creator' : 'Seat ${i + 1}'),
              trailing: i == client.seat
                  ? const Chip(label: Text('You'))
                  : null,
            ),
          const SizedBox(height: 12),
          if (client.seat == 0)
            FilledButton(
              onPressed:
                  client.connected &&
                      client.players.length + client.botCount == client.capacity
                  ? client.start
                  : null,
              child: const Text('Start match'),
            )
          else
            const Text('The creator starts once all players join.'),
          const SizedBox(height: 12),
          const Text(
            'Seat tokens are stored on this device for reconnection. '
            'Keep the host running throughout the match.',
          ),
        ],
      ),
    ),
  );
}
