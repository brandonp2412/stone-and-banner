import 'package:flutter_test/flutter_test.dart';
import 'package:stone_and_banner/ui/resource_label.dart';

Finder resourceLabel(String text, {bool contains = false}) =>
    find.byWidgetPredicate(
      (widget) =>
          widget is ResourceLabel &&
          (contains ? widget.text.contains(text) : widget.text == text),
    );
