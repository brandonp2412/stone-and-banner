import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/lan_client.dart';
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
  final boardSeed = TextEditingController(text: '20261027');
  String? savedRoom, savedToken;
  bool host = true;
  int seats = 3;

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
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      address.text = prefs.getString('lanUrl') ?? address.text;
      savedRoom = prefs.getString('lanRoom');
      savedToken = prefs.getString('lanToken');
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

  void _createOrJoin() {
    if (host) {
      final seed = int.tryParse(boardSeed.text);
      if (seed == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a numeric board seed.')),
        );
        return;
      }
      client.host(address.text, name.text, seats, seed);
    } else {
      client.join(address.text, name.text, roomCode.text);
    }
  }

  @override
  void dispose() {
    client.removeListener(_refresh);
    client.dispose();
    address.dispose();
    name.dispose();
    roomCode.dispose();
    boardSeed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = client.game;
    final seat = client.seat;
    final activeSeat = state?.tactical?.responder ?? state?.active;
    final canAct =
        client.connected &&
        !client.pending &&
        state != null &&
        seat == activeSeat;
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
      appBar: AppBar(title: const Text('LAN multiplayer')),
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
          if (client.room == null)
            Expanded(child: _setup())
          else if (state == null)
            Expanded(child: _lobby())
          else
            Expanded(
              child: Stack(
                children: [
                  AbsorbPointer(
                    absorbing: !canAct,
                    child: MatchView(
                      state: state,
                      online: true,
                      onlineView: client.view,
                      onEvent: client.dispatch,
                    ),
                  ),
                  if (!canAct)
                    Positioned(
                      top: 8,
                      left: 12,
                      right: 12,
                      child: Card(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const Icon(Icons.sync),
                              const SizedBox(width: 10),
                              Expanded(child: Text(wait)),
                            ],
                          ),
                        ),
                      ),
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
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Connect to a private LAN host',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'All players connect to the same private LAN host. '
            'Remote internet games are not enabled.',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: address,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Host WebSocket URL',
              helperText: 'Example: ws://host.example.test:8765/room',
            ),
          ),
          const SizedBox(height: 14),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Create room')),
              ButtonSegment(value: false, label: Text('Join room')),
            ],
            selected: {host},
            onSelectionChanged: (value) => setState(() => host = value.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: name,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Your player name',
            ),
          ),
          const SizedBox(height: 12),
          if (host) ...[
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 3, label: Text('3 players')),
                ButtonSegment(value: 4, label: Text('4 players')),
              ],
              selected: {seats},
              onSelectionChanged: (value) =>
                  setState(() => seats = value.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: boardSeed,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Board seed',
              ),
            ),
          ] else
            TextField(
              controller: roomCode,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Room code',
              ),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: client.connecting ? null : _createOrJoin,
            child: Text(
              client.connecting
                  ? 'Connecting…'
                  : host
                  ? 'Create LAN room'
                  : 'Join LAN room',
            ),
          ),
          if (savedRoom != null && savedToken != null) ...[
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: client.connecting
                  ? null
                  : () => client.resume(address.text, savedRoom!, savedToken!),
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
          OutlinedButton.icon(
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: client.room!)),
            icon: const Icon(Icons.copy),
            label: const Text('Copy invite code'),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < client.capacity; i++)
            ListTile(
              leading: Icon(
                i < client.connectedPlayers.length && client.connectedPlayers[i]
                    ? Icons.wifi
                    : Icons.wifi_off,
              ),
              title: Text(
                i < client.players.length
                    ? client.players[i]
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
                  client.connected && client.players.length == client.capacity
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
