import 'labels.dart';

import 'dart:ui' as ui;

import 'compact_layout.dart';

import 'package:flutter/material.dart';

import 'game_colors.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/board.dart';

enum ResourceIconStyle {
  banner('Banner', 'banner', 'Bold resource colours and familiar silhouettes'),
  treasury(
    'Treasury',
    'treasury',
    'Rich jewel colours and warm golden highlights',
  ),
  carvedStone(
    'Carved Stone',
    'carved-stone',
    'Cool mineral colours with bright, clear edges',
  ),
  gameIcons(
    'Game Icons',
    'game-icons',
    'Game resource silhouettes · CC BY 3.0',
  ),
  pictogrammers('Pictogrammers', 'mdi', 'Compact solid symbols · Apache 2.0'),
  fluent('Fluent Emoji', 'fluent-emoji-flat', 'Microsoft flat colour · MIT'),
  noto('Noto Emoji', 'noto', 'Google illustrated colour · Apache 2.0'),
  twemoji('Twemoji', 'twemoji', 'Bold flat colour · CC BY 4.0');

  const ResourceIconStyle(this.label, this.folder, this.description);
  final String label;
  final String folder;
  final String description;
}

final resourceIconStyle = ValueNotifier(ResourceIconStyle.banner);
final resourceIconsRevision = ValueNotifier(0);
final _images = <ResourceIconStyle, Map<Resource, ui.Image>>{};
Future<void>? _loading;

String resourceIconAsset(ResourceIconStyle style, Resource resource) =>
    'assets/icons/${style.folder}/${resource.name}.png';

/// Load once for both canvas terrain and widgets. Assets remain available offline.
Future<void> loadResourceIcons() => _loading ??= _loadResourceIcons();

Future<void> _loadResourceIcons() async {
  await Future.wait(
    ResourceIconStyle.values.map((style) async {
      final images = <Resource, ui.Image>{};
      await Future.wait(
        Resource.values.map((resource) async {
          final data = await rootBundle.load(
            resourceIconAsset(style, resource),
          );
          final codec = await ui.instantiateImageCodec(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
          images[resource] = (await codec.getNextFrame()).image;
          codec.dispose();
        }),
      );
      _images[style] = images;
    }),
  );
  resourceIconsRevision.value++;
}

Future<void> restoreResourceIconStyle() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('resource_icon_pack');
  resourceIconStyle.value = ResourceIconStyle.banner;
  for (final style in ResourceIconStyle.values) {
    if (style.name == saved) resourceIconStyle.value = style;
  }
}

Future<void> selectResourceIconStyle(ResourceIconStyle style) async {
  if (!_images.containsKey(style)) await loadResourceIcons();
  resourceIconStyle.value = style;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('resource_icon_pack', style.name);
}

class ResourceIcon extends StatelessWidget {
  const ResourceIcon(this.resource, {super.key, this.size = 28, this.style});
  final Resource resource;
  final double size;
  final ResourceIconStyle? style;

  @override
  Widget build(BuildContext context) {
    loadResourceIcons();
    return Semantics(
      label: resource.displayName,
      image: true,
      child: ValueListenableBuilder<ResourceIconStyle>(
        valueListenable: resourceIconStyle,
        builder: (context, selected, _) => ValueListenableBuilder<int>(
          valueListenable: resourceIconsRevision,
          builder: (context, revision, _) => RawImage(
            image: _images[style ?? selected]?[resource],
            width: size,
            height: size,
            fit: BoxFit.contain,
            // Silhouette packs use pale gold artwork for the dark board.
            // Give their UI previews and inventory icons a readable light ink.
            color:
                Theme.of(context).brightness == Brightness.light &&
                    {
                      ResourceIconStyle.gameIcons,
                      ResourceIconStyle.pictogrammers,
                    }.contains(style ?? selected)
                ? gameColor(context, const Color(0xffe5c183))
                : null,
            colorBlendMode: BlendMode.srcIn,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}

void paintResourceIcon(
  Canvas canvas,
  Offset center,
  double size,
  Resource resource,
) {
  final image = _images[resourceIconStyle.value]?[resource];
  if (image == null) return;
  // Fit within the requested square without changing the source proportions.
  final scale =
      size / (image.width > image.height ? image.width : image.height);
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    Rect.fromCenter(
      center: center,
      width: image.width * scale,
      height: image.height * scale,
    ),
    Paint()..filterQuality = FilterQuality.medium,
  );
}

Future<void> showResourceIconPicker(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => CompactAlertDialog(
    title: const Text('Resource icons'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: ValueListenableBuilder<ResourceIconStyle>(
          valueListenable: resourceIconStyle,
          builder: (context, selected, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final style in ResourceIconStyle.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: selected == style
                        ? gameColor(context, const Color(0xff354b50))
                        : gameColor(context, const Color(0xff182c34)),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => selectResourceIconStyle(style),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    style.label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (selected == style)
                                  const Icon(Icons.check, size: 18),
                              ],
                            ),
                            Text(
                              style.description,
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                for (final resource in Resource.values)
                                  Expanded(
                                    child: Tooltip(
                                      message: resource.displayName,
                                      child: Center(
                                        child: ResourceIcon(
                                          resource,
                                          size: 28,
                                          style: style,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              TextButton(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: 'Stone & Banner',
                ),
                child: const Text('Icon credits and licences'),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  ),
);

void registerResourceIconLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Resource icon artwork',
    ], await rootBundle.loadString('assets/icons/NOTICE.md'));
    for (final style in ResourceIconStyle.values) {
      yield LicenseEntryWithLineBreaks(
        [style.label],
        await rootBundle.loadString('assets/icons/${style.folder}/LICENSE.txt'),
      );
    }
  });
}
