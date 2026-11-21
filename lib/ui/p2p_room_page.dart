import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/world_seed.dart';
import '../network/p2p_links.dart';
import '../network/p2p_room.dart';
import '../network/p2p_transport.dart';
import 'match_screen.dart';
import 'lan_room_page.dart';

class P2pRoomPage extends StatefulWidget {
  const P2pRoomPage({super.key});
  @override
  State<P2pRoomPage> createState() => _P2pRoomPageState();
}

class _P2pRoomPageState extends State<P2pRoomPage> {
  late final P2pRoom room;
  final name = TextEditingController(text: 'Host');
  final answerField = TextEditingController();
  final inviteField = TextEditingController();
  Map<String, dynamic>? incoming;
  String? parseError;
  int seats = 3;
  bool applying = false;
  bool? responseDelivered;
  bool forwardingResponse = false;
  String? receivedResponseLink;

  Future<void> _deliverResponse(String link) async {
    if (forwardingResponse) return;
    setState(() {
      forwardingResponse = true;
      responseDelivered = null;
    });
    final delivered = await P2pTransport.forwardAnswer(link);
    if (!mounted) return;
    setState(() {
      responseDelivered = delivered;
      forwardingResponse = false;
    });
  }

  @override
  void initState() {
    super.initState();
    room = P2pRoom()..addListener(_refresh);
    final incomingLink = P2pTransport.initialLink();
    if (incomingLink != null) {
      try {
        incoming = P2pLinks.parse(incomingLink);
        if (incoming!['type'] == 'offer') name.text = 'Guest';
        if (incoming!['type'] == 'answer') {
          receivedResponseLink = incomingLink;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _deliverResponse(incomingLink);
          });
        }
      } on Object catch (e) {
        parseError = '$e';
      }
    }
  }

  void _useInviteLink() {
    try {
      final value = P2pLinks.parse(inviteField.text);
      if (value['type'] != 'offer') {
        throw const FormatException('Paste a host invitation, not a response.');
      }
      setState(() {
        incoming = value;
        name.text = 'Guest';
        parseError = null;
      });
    } on Object catch (e) {
      setState(() => parseError = '$e');
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
    inviteField.dispose();
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

  bool _copyingDiagnostics = false;

  Future<void> _copyDiagnostics() async {
    if (_copyingDiagnostics) return;
    setState(() => _copyingDiagnostics = true);
    try {
      final report = await room.diagnosticReport(uiError: parseError);
      await Clipboard.setData(ClipboardData(text: report));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connection diagnostics copied')),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => parseError = 'Could not copy diagnostics: $error');
      }
    } finally {
      if (mounted) setState(() => _copyingDiagnostics = false);
    }
  }

  Widget _copyDiagnosticsButton() => OutlinedButton.icon(
    onPressed: _copyingDiagnostics ? null : _copyDiagnostics,
    icon: const Icon(Icons.content_copy, size: 18),
    label: Text(
      _copyingDiagnostics
          ? 'Collecting diagnostics…'
          : 'Copy connection diagnostics',
    ),
  );

  Widget _pane(List<Widget> children) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 590),
      child: ListView(padding: const EdgeInsets.all(20), children: children),
    ),
  );

  Widget _setup() => incoming?['type'] == 'answer'
      ? _answerPage()
      : _pane([
          Text(
            kIsWeb ? 'Host or join a game' : 'Direct P2P multiplayer',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Host directly from this device. No game server or account required. '
            'To connect, your friend opens your invite and sends the response '
            'back to you. Apply their response in this host lobby to finish pairing.',
          ),
          if (kIsWeb) ...[
            const SizedBox(height: 8),
            const Text(
              'Browser and native apps use peer-to-peer WebRTC here. '
              'The connection can stay entirely on your local Wi-Fi.',
            ),
          ],
          const SizedBox(height: 14),
          if (incoming == null) ...[
            const SizedBox(height: 8),
            TextField(
              controller: inviteField,
              minLines: 1,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Invitation link from friend',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: _useInviteLink,
              icon: const Icon(Icons.link),
              label: const Text('Join from invitation'),
            ),
          ],
          TextField(
            controller: name,
            maxLength: 32,
            decoration: const InputDecoration(
              labelText: 'Your player name',
              border: OutlineInputBorder(),
            ),
          ),
          if (incoming?['type'] == 'offer') ...[
            const Text(
              'Invitation received. Join to generate a response link.',
            ),
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
          ] else ...[
            const Text(
              'Create a room and send a separate invitation to each guest.',
            ),
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
              label: Text(
                kIsWeb
                    ? 'Host game'
                    : 'Host game (Android, iPhone, web, Linux)',
              ),
            ),
            if (!kIsWeb) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const LanRoomPage()),
                ),
                icon: const Icon(Icons.settings_ethernet),
                label: const Text(
                  'Advanced: native-app LAN rooms (Android/Linux only)',
                ),
              ),
            ],
          ],
        ]);

  /// A response should never look like a new host lobby.
  Widget _answerPage() => _pane([
    Text(
      'Connection response',
      style: Theme.of(context).textTheme.headlineSmall,
    ),
    const SizedBox(height: 12),
    if (forwardingResponse)
      const ListTile(
        leading: CircularProgressIndicator(),
        title: Text('Sending response to your original host tab…'),
        subtitle: Text('Keep the host tab open. This page is not a lobby.'),
      )
    else if (responseDelivered == true)
      const ListTile(
        leading: Icon(Icons.check_circle_outline),
        title: Text('Response applied to your host lobby'),
        subtitle: Text(
          'Return to the original host tab to see your friend join. '
          'You do not need to host again.',
        ),
      )
    else
      const ListTile(
        leading: Icon(Icons.info_outline),
        title: Text('Original host tab not found'),
        subtitle: Text(
          'This response page cannot become your host room. '
          'Switch to your existing host tab and paste the link into '
          '“Response link from friend”. If the host tab was replaced, '
          'recreate the lobby and send a new invitation. '
          'Links must open in the same browser, not an in-app browser.',
        ),
      ),
    const SizedBox(height: 8),
    OutlinedButton.icon(
      onPressed: forwardingResponse || receivedResponseLink == null
          ? null
          : () => _deliverResponse(receivedResponseLink!),
      icon: const Icon(Icons.send_outlined),
      label: const Text('Try sending to open host tab again'),
    ),
    const SizedBox(height: 8),
    _copy('response link', receivedResponseLink ?? ''),
  ]);

  Widget _lobby() => _pane([
    Text(
      'P2P room ${room.roomId ?? ''}',
      style: Theme.of(context).textTheme.headlineSmall,
    ),
    const SizedBox(height: 7),
    Text(
      room.isHost
          ? 'You are the authoritative host. Keep this session open when your '
                'friend replies; never replace it with their link.'
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
        'Your friend must send a response link back because WebRTC needs '
        'connection details from both devices. Keep this host session open. '
        'On web, open their response link in another tab in the SAME browser '
        '(it applies automatically), or paste the response below on any platform.',
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
        'Send this link back to the host. Keep both apps or browser tabs open.',
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
    _copyDiagnosticsButton(),
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
          ? AppBar(title: Text(kIsWeb ? 'Multiplayer' : 'P2P multiplayer'))
          : null,
      body: Column(
        children: [
          if (parseError != null || room.message != null)
            MaterialBanner(
              content: Text(parseError ?? room.message!),
              actions: [
                TextButton.icon(
                  onPressed: _copyingDiagnostics ? null : _copyDiagnostics,
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy diagnostics'),
                ),
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
