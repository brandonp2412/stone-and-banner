import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/ui/match_screen.dart';
import 'package:stone_and_banner/ui/resource_icon.dart';

import 'landscape_tabletop_test.dart' show tableWithSupplies;

void main() {
  testWidgets('options sheet rebuilds after the match is removed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final showMatch = ValueNotifier(true);
    addTearDown(showMatch.dispose);
    await tester.runAsync(loadResourceIcons);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: showMatch,
          builder: (context, visible, child) => Scaffold(
            body: visible
                ? MatchView(
                    state: tableWithSupplies(),
                    online: true,
                    viewingSeat: 0,
                    onEvent: (_) {},
                    onLeaveRoom: () {},
                  )
                : const Text('Room closed'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('match-room-menu')));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    showMatch.value = false;
    await tester.pumpAndSettle();
    // Force the surviving modal to rebuild its responsive layout.
    tester.view.physicalSize = const Size(420, 800);
    await tester.pumpAndSettle();
    expect(find.text('Gameplay hints'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile room exit is in top-left menu, not over reactions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(780, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var leaveRequests = 0;
    await tester.runAsync(loadResourceIcons);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: Scaffold(
          body: MatchView(
            state: tableWithSupplies(),
            online: true,
            viewingSeat: 0,
            onEvent: (_) {},
            onLeaveRoom: () => leaveRequests++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final menu = find.byKey(const ValueKey('match-room-menu'));
    expect(menu, findsOneWidget);
    expect(find.byTooltip('Leave P2P match'), findsNothing);
    expect(find.byTooltip('Leave LAN match'), findsNothing);
    expect(
      tester.getRect(menu).right,
      lessThan(tester.getRect(find.byTooltip('React')).left),
    );

    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('match-leave-room-menu')), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/mobile_room_exit_menu.png'),
    );
    await tester.tap(find.byKey(const ValueKey('match-leave-room-menu')));
    await tester.pumpAndSettle();
    expect(leaveRequests, 1);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
