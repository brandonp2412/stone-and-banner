import 'dart:async';

import 'package:flutter/foundation.dart';

import 'compact_layout.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/world_seed.dart';
import '../network/p2p_links.dart';
import '../network/p2p_room.dart';
import '../network/p2p_transport.dart';
import 'match_screen.dart';
import 'lan_room_page.dart';

class P2pRoomPage extends StatefulWidget {
  const P2pRoomPage({super.key, this.onExitToHome});

  final VoidCallback? onExitToHome;

  @override
  State<P2pRoomPage> createState() => _P2pRoomPageState();
}

class _P2pRoomPageState extends State<P2pRoomPage> with WidgetsBindingObserver {
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
  bool _leaveApproved = false;
  bool _leavePromptOpen = false;
  bool _serviceStarted = false;
  static const _service = MethodChannel('stone_and_banner/multiplayer');

  void _syncBackgroundService() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final shouldRun = room.roomId != null;
    if (shouldRun == _serviceStarted) return;
    _serviceStarted = shouldRun;
    unawaited(
      _service.invokeMethod<void>(shouldRun ? 'start' : 'stop').catchError((
        Object error,
      ) {
        if (mounted && shouldRun) {
          room.message =
              'Android could not protect the background connection: $error';
          setState(() {});
        }
      }),
    );
  }

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
    WidgetsBinding.instance.addObserver(this);
    room = P2pRoom(shuffleTurns: true)..addListener(_refresh);
    final incomingLink = P2pTransport.initialLink();
    if (incomingLink != null) {
      try {
        incoming = P2pLinks.parse(incomingLink);
        if (incoming!['type'] == 'offer' || incoming!['type'] == 'room') {
          name.text = 'Guest';
        }
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
      if (value['type'] != 'offer' && value['type'] != 'room') {
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
    if (!mounted) return;
    _syncBackgroundService();
    setState(() {});
  }

  void _exitRoom() {
    if (widget.onExitToHome case final leaveToHome?) {
      leaveToHome();
      return;
    }
    Navigator.of(context).maybePop();
  }

  Future<void> _requestLeave() async {
    if (_leavePromptOpen || _leaveApproved) return;
    if (room.roomId == null) {
      _exitRoom();
      return;
    }
    _leavePromptOpen = true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => CompactAlertDialog(
        title: const Text('Leave multiplayer?'),
        content: const Text(
          'Leaving closes this peer-to-peer connection. If you are hosting, '
          'everyone will lose their connection to the match.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Stay in room'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Leave room'),
          ),
        ],
      ),
    );
    _leavePromptOpen = false;
    if (!mounted || leave != true) return;
    if (widget.onExitToHome != null) {
      _exitRoom();
      return;
    }
    setState(() => _leaveApproved = true);
    // PopScope reads canPop from the next frame. Never tear down an active
    // host room because the IME or Android back navigation issued a pop.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _exitRoom();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      room.ensureInvitesConnected();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    room.removeListener(_refresh);
    if (_serviceStarted) {
      _serviceStarted = false;
      unawaited(_service.invokeMethod<void>('stop').catchError((Object _) {}));
    }
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
      constraints: BoxConstraints(
        maxWidth: isCompactLandscape(context) ? 730 : 590,
      ),
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
                        key: const ValueKey('multiplayer-back'),
                        tooltip: 'Back',
                        onPressed: _requestLeave,
                        icon: const Icon(Icons.arrow_back),
                        padding: EdgeInsets.zero,
                      ),
                    )
                  : TextButton.icon(
                      onPressed: _requestLeave,
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Back'),
                    ),
            ),
          ...children,
        ],
      ),
    ),
  );

  /// Host and join are independent flows, so lay them out side-by-side on
  /// a phone in landscape rather than pushing Host below the first screen.
  Widget _compactSetup() => SafeArea(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        children: [
          CompactPageHeader(title: 'Multiplayer', onBack: _requestLeave),
          const Divider(height: 1),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(4, 8, 12, 4),
                    children: [
                      Text(
                        'Join a friend',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: inviteField,
                        maxLines: 1,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'Invitation link',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _useInviteLink,
                        icon: const Icon(Icons.link),
                        label: const Text('Join invitation'),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Open the invite and return a response link to your host.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
                    children: [
                      Text(
                        'Host a game',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: name,
                        maxLength: 32,
                        decoration: const InputDecoration(
                          isDense: true,
                          counterText: '',
                          labelText: 'Your player name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
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
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: () {
                          try {
                            room.host(name.text, seats, randomWorldSeed());
                          } on Object catch (e) {
                            setState(() => parseError = '$e');
                          }
                        },
                        icon: const Icon(Icons.groups),
                        label: const Text('Host game'),
                      ),
                      if (!kIsWeb)
                        TextButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const LanRoomPage(),
                            ),
                          ),
                          icon: const Icon(Icons.settings_ethernet),
                          label: const Text('Advanced LAN mode'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _setup() => incoming?['type'] == 'answer'
      ? _answerPage()
      : isCompactLandscape(context) && incoming == null
      ? _compactSetup()
      : _pane([
          Text(
            kIsWeb ? 'Host or join a game' : 'Direct P2P multiplayer',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            incoming?['type'] == 'room'
                ? 'You have been invited. Enter your name and join.'
                : 'Host a game and share one invite with everyone. '
                      'The connection is negotiated automatically.',
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
          if (incoming?['type'] == 'offer' || incoming?['type'] == 'room') ...[
            Text(
              incoming?['type'] == 'room'
                  ? 'Invitation received. Join to connect automatically.'
                  : 'Invitation received. Join to generate a response link.',
            ),
            if (room.joiningOneLink && room.joinStatus != null) ...[
              const SizedBox(height: 8),
              Text(room.joinStatus!),
            ],
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: room.preparing || room.joiningOneLink
                  ? null
                  : () async {
                      try {
                        if (incoming!['type'] == 'room') {
                          await room.joinByRoomLink(
                            name.text,
                            incoming!['key'] as String,
                          );
                        } else {
                          await room.join(name.text, incoming!);
                          // Same-browser guests can deliver the response immediately,
                          // before manual signalling allows ICE checks to time out.
                          // Other browsers still offer the copyable response link.
                          final answer = room.answerLink;
                          if (kIsWeb && answer != null) {
                            unawaited(_deliverResponse(answer));
                          }
                        }
                      } on Object catch (e) {
                        setState(() => parseError = '$e');
                      }
                    },
              icon: const Icon(Icons.link),
              label: Text(
                room.joiningOneLink
                    ? 'Joining automatically…'
                    : room.preparing
                    ? 'Collecting candidates…'
                    : incoming?['type'] == 'room'
                    ? 'Join game'
                    : 'Join and create response',
              ),
            ),
          ] else ...[
            const Text(
              'Create a room and share one invite link with your friends.',
            ),
            const SizedBox(height: 9),
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
                    },
                  ),
              ],
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
        subtitle: Text(
          'Switch to the original host tab now. Both tabs must '
          'be in the same browser; otherwise copy the link below and '
          'paste it into the host lobby.',
        ),
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

  /// The old offer/response workflow remains available when signalling is
  /// offline. Hide it during normal one-link hosting.
  Widget _manualPairing() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
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
    ],
  );

  Widget _lobby() => _pane([
    Text(
      'P2P room ${room.roomId ?? ''}',
      style: Theme.of(context).textTheme.headlineSmall,
    ),
    const SizedBox(height: 7),
    Text(
      room.isHost
          ? 'You are hosting. Share one invitation with your friends.'
          : room.connected
          ? 'Connected to host · Seat ${room.seat! + 1}'
          : room.oneLinkGuest
          ? 'Connecting to the host automatically…'
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
            tooltip: 'Remove bot opponent',
            onPressed: room.botCount > 0 && !room.started
                ? () => room.setBotCount(room.botCount - 1)
                : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          IconButton(
            tooltip: 'Add bot opponent',
            onPressed: room.botCount < room.availableBotSeats && !room.started
                ? () => room.setBotCount(room.botCount + 1)
                : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      Text(
        'Fill any empty seats with the same bots as solo play. '
        'Friends always keep their own seats.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      if (room.signallingPreparing)
        const Text('Preparing your one-link invitation…'),
      if (room.roomLink case final String link) ...[
        const Text('Share this link with everyone joining your game:'),
        const SizedBox(height: 8),
        _copy('room invitation', link),
      ],
      if (room.signallingError case final String error)
        Text(error, style: Theme.of(context).textTheme.bodySmall),
      if (!room.signallingPreparing && room.roomLink == null)
        _manualPairing()
      else
        ExpansionTile(
          title: const Text('Advanced: manual pairing fallback'),
          tilePadding: EdgeInsets.zero,
          children: [_manualPairing()],
        ),
    ] else if (room.oneLinkGuest && !room.connected) ...[
      const Text(
        'Not connected yet? If your player name is taken, '
        'choose another and retry without reopening the invite.',
      ),
      const SizedBox(height: 8),
      TextField(
        controller: name,
        decoration: const InputDecoration(
          labelText: 'Player name',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 6),
      OutlinedButton(
        onPressed: () => room.retryName(name.text),
        child: const Text('Retry with this name'),
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
        visualDensity: isCompactLandscape(context)
            ? VisualDensity.compact
            : VisualDensity.standard,
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
                    ? '${room.players[i]} · Bot'
                    : room.players[i]
              : room.botSeats.contains(i)
              ? 'Bot opponent (reserved)'
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
              : 'Start with ${room.botCount} bot opponent${room.botCount == 1 ? '' : 's'}',
        ),
      ),
    const SizedBox(height: 12),
    _copyDiagnosticsButton(),
    const SizedBox(height: 12),
    const Text(
      'WebRTC tries a direct connection first. Restrictive NATs can use '
      'the encrypted free TURN relay; if its monthly quota is exhausted, '
      'only direct connections remain. Your IP may be visible to peers '
      'and STUN servers.',
    ),
  ]);

  @override
  Widget build(BuildContext context) {
    final game = room.game;
    final active = game?.actingSeat;
    // Responding to an active player's trade is legal outside your turn.
    // The response sheet must not become read-only for online recipients.
    final canPlayTurn =
        room.connected && !room.pending && game != null && room.seat == active;
    // Responding to a trade is a limited permission, not turn ownership.
    // End turn must remain hidden/disabled until this player's actual turn.
    final canReplyToTrade =
        room.connected &&
        !room.pending &&
        game != null &&
        room.seat != null &&
        game.offers.any(
          (offer) =>
              offer.proposer == game.active && offer.canRespond(room.seat!),
        );
    return PopScope(
      canPop: _leaveApproved || room.roomId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_leaveApproved) _requestLeave();
      },
      child: Scaffold(
        appBar: game == null && MediaQuery.sizeOf(context).width >= 900
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
                          observing: !canPlayTurn,
                          onFastForward: room.connected && room.botsActing
                              ? room.fastForwardBots
                              : null,
                          tradeReplyAllowed: canReplyToTrade,
                          waitingMessage: canPlayTurn
                              ? null
                              : room.connected
                              ? 'Waiting for ${game.players[active!].id}…'
                              : 'Direct connection lost',
                          onEvent: room.dispatch,
                          onEmote: room.sendEmote,
                          networkEmote: room.emote,
                          networkEmoteSeat: room.emoteSeat,
                          networkEmoteSerial: room.emoteSerial,
                          onLeaveRoom: _requestLeave,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
