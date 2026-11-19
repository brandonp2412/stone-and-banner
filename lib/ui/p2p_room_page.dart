import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/world_seed.dart';
import '../network/p2p_links.dart';
import '../network/p2p_room.dart';
import '../network/p2p_transport.dart';
import 'match_screen.dart';

class P2pRoomPage extends StatefulWidget {
  const P2pRoomPage({super.key});
  @override
  State<P2pRoomPage> createState() => _P2pRoomPageState();
}

class _P2pRoomPageState extends State<P2pRoomPage> {
  late final P2pRoom room;
  final name = TextEditingController(text: 'Host');
  final answerField = TextEditingController();
  Map<String, dynamic>? incoming;
  String? parseError;
  int seats = 3;
  bool applying = false;

  @override
  void initState() {
    super.initState();
    room = P2pRoom()..addListener(_refresh);
    final incomingLink = kIsWeb ? P2pTransport.initialLink() : null;
    if (incomingLink != null) {
      try {
        incoming = P2pLinks.parse(incomingLink);
        if (incoming!['type'] == 'offer') name.text = 'Guest';
        if (incoming!['type'] == 'answer') {
          // Host's original tab receives this via BroadcastChannel.
          P2pTransport.broadcastAnswer(incomingLink);
        }
      } on Object catch (e) {
        parseError = '$e';
      }
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    room.removeListener(_refresh);
    room.dispose();
    name.dispose();
    answerField.dispose();
    super.dispose();
  }

  Widget _copy(String label, String link) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      TextFormField(
        key: ValueKey(link),
        initialValue: link,
        readOnly: true,
        maxLines: 2,
        minLines: 1,
        style: const TextStyle(fontSize: 11),
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      const SizedBox(height: 6),
      FilledButton.tonalIcon(
        onPressed: () => Clipboard.setData(ClipboardData(text: link)),
        icon: const Icon(Icons.copy),
        label: Text('Copy $label'),
      ),
    ],
  );

  Widget _pane(List<Widget> children) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 590),
      child: ListView(padding: const EdgeInsets.all(20), children: children),
    ),
  );

  Widget _setup() => _pane([
    Text(
      'Direct P2P multiplayer',
      style: Theme.of(context).textTheme.headlineSmall,
    ),
    const SizedBox(height: 8),
    const Text(
      'No signalling server, relay, or accounts. '
      'Free public STUN servers help peers traverse home routers; game moves '
      'stay encrypted and direct. Exchange invitation and response links '
      'over chat. Some NATs and firewalls still block connections.',
    ),
    const SizedBox(height: 14),
    TextField(
      controller: name,
      maxLength: 32,
      decoration: const InputDecoration(
        labelText: 'Your player name',
        border: OutlineInputBorder(),
      ),
    ),
    if (incoming?['type'] == 'offer') ...[
      const Text('Invitation received. Join to generate a response link.'),
      const SizedBox(height: 10),
      FilledButton.icon(
        onPressed: room.preparing
            ? null
            : () async {
                try {
                  await room.join(name.text, incoming!);
                } on Object catch (e) {
                  setState(() => parseError = '$e');
                }
              },
        icon: const Icon(Icons.link),
        label: Text(
          room.preparing
              ? 'Collecting candidates…'
              : 'Join and create response',
        ),
      ),
    ] else if (incoming?['type'] == 'answer') ...[
      const Text(
        'Response forwarded to any open host tab. '
        'If it was not applied, paste this link into your original host tab. '
        'Do not close or replace the host tab.',
      ),
      _copy('response link', P2pTransport.initialLink() ?? ''),
    ] else ...[
      const Text('Create a room and send a separate invitation to each guest.'),
      const SizedBox(height: 9),
      SegmentedButton<int>(
        selected: {seats},
        segments: const [
          ButtonSegment(value: 3, label: Text('3 players')),
          ButtonSegment(value: 4, label: Text('4 players')),
        ],
        onSelectionChanged: (v) => setState(() => seats = v.first),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: () {
          try {
            room.host(name.text, seats, randomWorldSeed());
          } on Object catch (e) {
            setState(() => parseError = '$e');
          }
        },
        icon: const Icon(Icons.groups),
        label: const Text('Host P2P match'),
      ),
    ],
  ]);

  Widget _lobby() => _pane([
    Text(
      'P2P room ${room.roomId ?? ''}',
      style: Theme.of(context).textTheme.headlineSmall,
    ),
    const SizedBox(height: 7),
    Text(
      room.isHost
          ? 'You are the authoritative host. Keep this tab open.'
          : room.connected
          ? 'Connected to host · Seat ${room.seat! + 1}'
          : 'Waiting for the host to apply your response link…',
    ),
    const SizedBox(height: 10),
    if (room.isHost) ...[
      Row(
        children: [
          const Icon(Icons.smart_toy_outlined, size: 21),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Computer opponents: ${room.botCount}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: 'Remove AI opponent',
            onPressed: room.botCount > 0 && !room.started
                ? () => room.setBotCount(room.botCount - 1)
                : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          IconButton(
            tooltip: 'Add AI opponent',
            onPressed: room.botCount < room.availableBotSeats && !room.started
                ? () => room.setBotCount(room.botCount + 1)
                : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      Text(
        'Fill any empty seats with the same AI as solo play. '
        'Friends always keep their own seats.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      FilledButton.tonalIcon(
        onPressed: room.preparing || room.started
            ? null
            : () async {
                try {
                  await room.invite();
                } on Object catch (e) {
                  setState(() => parseError = '$e');
                }
              },
        icon: const Icon(Icons.person_add),
        label: Text(
          room.preparing
              ? 'Gathering candidates…'
              : 'Generate invite for next player',
        ),
      ),
      if (room.invitationLink case final String link) ...[
        const SizedBox(height: 10),
        _copy('invite link', link),
      ],
      TextButton.icon(
        onPressed: room.preparing || room.started
            ? null
            : room.clearUnusedInvites,
        icon: const Icon(Icons.refresh),
        label: const Text('Replace expired or unused invitations'),
      ),
      const SizedBox(height: 14),
      const Text(
        'Friend opens the invite and sends back a response link. '
        'Paste it here, or open it in a NEW tab while keeping this tab open.',
      ),
      const SizedBox(height: 7),
      TextField(
        controller: answerField,
        minLines: 1,
        maxLines: 2,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'Response link from friend',
        ),
      ),
      const SizedBox(height: 6),
      OutlinedButton(
        onPressed: applying
            ? null
            : () async {
                setState(() {
                  applying = true;
                  parseError = null;
                });
                try {
                  await room.acceptAnswer(answerField.text);
                  answerField.clear();
                } on Object catch (e) {
                  parseError = '$e';
                } finally {
                  if (mounted) setState(() => applying = false);
                }
              },
        child: Text(applying ? 'Connecting…' : 'Apply response link'),
      ),
    ] else if (room.answerLink case final String link) ...[
      _copy('response link', link),
      const SizedBox(height: 7),
      const Text(
        'Send this link back to the host. Both tabs must remain open.',
      ),
      if (!room.connected) ...[
        const SizedBox(height: 9),
        TextField(
          controller: name,
          decoration: const InputDecoration(
            labelText: 'Player name (must be unique)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 5),
        OutlinedButton(
          onPressed: () => room.retryName(name.text),
          child: const Text('Retry joining with this name'),
        ),
      ],
    ],
    const SizedBox(height: 14),
    if (room.networkDiagnostic != null) ...[
      Text(
        room.networkDiagnostic!,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 6),
    ],
    if (room.connectionPath != null) ...[
      Row(
        children: [
          const Icon(Icons.lock_outline, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              room.connectionPath!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
    ],
    Text('Players', style: Theme.of(context).textTheme.titleMedium),
    for (var i = 0; i < room.capacity; i++)
      ListTile(
        dense: true,
        leading: Icon(
          room.botSeats.contains(i)
              ? Icons.smart_toy_outlined
              : i < room.connectedPlayers.length && room.connectedPlayers[i]
              ? Icons.link
              : Icons.link_off,
        ),
        title: Text(
          i < room.players.length
              ? room.botSeats.contains(i)
                    ? '${room.players[i]} · AI'
                    : room.players[i]
              : room.botSeats.contains(i)
              ? 'AI opponent (reserved)'
              : 'Waiting for player…',
        ),
        subtitle: Text('Seat ${i + 1}'),
      ),
    if (room.isHost)
      FilledButton.icon(
        onPressed: room.canStart
            ? () {
                try {
                  room.start();
                } on Object catch (error) {
                  setState(() => parseError = '$error');
                }
              }
            : null,
        icon: const Icon(Icons.play_arrow),
        label: Text(
          room.botCount == 0
              ? 'Start multiplayer match'
              : 'Start with ${room.botCount} AI opponent${room.botCount == 1 ? '' : 's'}',
        ),
      ),
    const SizedBox(height: 12),
    const Text(
      'Public STUN only discovers addresses; gameplay never traverses a '
      'relay. If blocked by CGNAT or restrictive firewalls, direct '
      'connections cannot be guaranteed. Your public IP may be visible '
      'to your peers and STUN operators.',
    ),
  ]);

  @override
  Widget build(BuildContext context) {
    final game = room.game;
    final active = game?.actingSeat;
    final canAct =
        room.connected && !room.pending && game != null && room.seat == active;
    return Scaffold(
      appBar: game == null
          ? AppBar(title: const Text('P2P multiplayer'))
          : null,
      body: Column(
        children: [
          if (parseError != null || room.message != null)
            MaterialBanner(
              content: Text(parseError ?? room.message!),
              actions: [
                TextButton(
                  onPressed: () => setState(() {
                    parseError = null;
                    room.message = null;
                  }),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          Expanded(
            child: game == null
                ? room.roomId == null
                      ? _setup()
                      : _lobby()
                : Stack(
                    children: [
                      MatchView(
                        state: game,
                        online: true,
                        onlineView: room.view,
                        viewingSeat: room.seat,
                        computerSeats: room.botSeats,
                        automationError: room.aiError,
                        onResumeAutomation: room.isHost ? room.retryBots : null,
                        observing: !canAct,
                        waitingMessage: canAct
                            ? null
                            : room.connected
                            ? 'Waiting for ${game.players[active!].id}…'
                            : 'Direct connection lost',
                        onEvent: room.dispatch,
                      ),
                      Positioned(
                        top: MediaQuery.paddingOf(context).top + 3,
                        right: MediaQuery.paddingOf(context).right + 4,
                        child: IconButton(
                          tooltip: 'Leave P2P match',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, size: 20),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
