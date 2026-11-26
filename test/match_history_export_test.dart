import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stone_and_banner/engine/match.dart';
import 'package:stone_and_banner/match_archive.dart';
import 'package:stone_and_banner/ui/match_history.dart';

class _Picker extends FilePickerPlatform {
  String? name;
  Uint8List? data;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    name = fileName;
    data = bytes;
    return Uri.file('/tmp/$fileName');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await (FontLoader('NotoSans')
          ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('export all saves exact replays and metadata on portrait', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final picker = _Picker();
    final previous = FilePickerPlatform.instance;
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = previous);
    for (final seed in [333, 334, 335]) {
      final state = MatchEngine.apply(
        MatchEngine.newGame(['Ada', 'Ben', 'Cora'], seed),
        const PlaceVillage(0),
      );
      await MatchArchive.save(prefs, state, computerSeats: {1, 2});
    }
    tester.view.physicalSize = const Size(393, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, fontFamily: 'NotoSans'),
        home: RepaintBoundary(
          key: const ValueKey('history-capture'),
          child: MatchHistoryPage(prefs: prefs),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('3 matches · 0 finished'), findsOneWidget);
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('STONE_VISUAL_CAPTURE')) {
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('history-capture')),
        );
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('/tmp/stone-history-portrait.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.tap(find.byTooltip('Export all matches'));
    await tester.pumpAndSettle();
    expect(picker.name, endsWith('.json'));
    final data = jsonDecode(utf8.decode(picker.data!)) as Map;
    expect(data['version'], 1);
    final entries = await MatchArchive.list(prefs);
    final matches = data['matches'] as List;
    expect(matches, hasLength(entries.length));
    for (var i = 0; i < entries.length; i++) {
      expect(matches[i], {
        ...entries[i].toJson(),
        'replay': MatchArchive.replay(prefs, entries[i]),
      });
      expect(
        MatchEngine.importReplay(matches[i]['replay'] as String).events,
        hasLength(1),
      );
    }
    expect(tester.takeException(), isNull);
  });
}
