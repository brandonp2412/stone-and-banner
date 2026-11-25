import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/ui/p2p_room_page.dart';

void main() {
  testWidgets('back navigation cannot silently terminate an active host room', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const P2pRoomPage()),
              ),
              child: const Text('Open multiplayer'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open multiplayer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Host game'));
    await tester.pumpAndSettle();
    expect(find.textContaining('P2P room'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Leave multiplayer?'), findsOneWidget);
    expect(find.textContaining('P2P room'), findsOneWidget);
    await tester.tap(find.text('Stay in room'));
    await tester.pumpAndSettle();
    expect(find.text('Leave multiplayer?'), findsNothing);
    expect(find.textContaining('P2P room'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave room'));
    await tester.pumpAndSettle();
    expect(find.text('Open multiplayer'), findsOneWidget);
  });
}
