import 'package:fei/ui/emoji_glyph.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Draws [child] centered in a transparent 100×100 box and returns where its
/// pixels landed.
Future<Rect> renderedInk(WidgetTester tester, Widget child) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(width: 100, height: 100, child: Center(child: child)),
        ),
      ),
    ),
  );
  // Lets EmojiInk's off-screen measurement finish, then repaints with it.
  // Its listeners hear in a microtask, so the shift lands a frame later.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump();
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData();
    image.dispose();
    return data!;
  });
  return inkBounds(bytes!.buffer.asUint8List(), 100, 100)!;
}

void main() {
  group('inkBounds', () {
    Uint8List image(int width, int height, List<(int, int, int)> pixels) {
      final rgba = Uint8List(width * height * 4);
      for (final (x, y, alpha) in pixels) {
        rgba[(y * width + x) * 4 + 3] = alpha;
      }
      return rgba;
    }

    test('finds the box around the opaque pixels', () {
      final rgba = image(10, 10, [(2, 3, 255), (6, 8, 200)]);
      expect(inkBounds(rgba, 10, 10), const Rect.fromLTRB(2, 3, 7, 9));
    });

    test('ignores faint anti-aliased pixels and empty images', () {
      expect(inkBounds(image(4, 4, [(1, 1, 10)]), 4, 4), isNull);
      expect(inkBounds(Uint8List(4 * 4 * 4), 4, 4), isNull);
    });
  });

  // In the test font, "p" is drawn entirely below the baseline, so as plain
  // text it sits low, the way 🚗 does in Noto Color Emoji.
  testWidgets('plain text leaves a low-drawn glyph off-center', (tester) async {
    final ink = await renderedInk(tester, Text('p', style: emojiTextStyle(40)));
    expect(ink.center.dy - 50, greaterThan(10));
  });

  testWidgets('EmojiGlyph centers the artwork, not the text box', (tester) async {
    final ink = await renderedInk(tester, const EmojiGlyph('p', size: 40));
    expect(ink.center.dx, closeTo(50, 1));
    expect(ink.center.dy, closeTo(50, 1));
  });

  testWidgets('the shift follows the user\'s text scaling', (tester) async {
    final ink = await renderedInk(
      tester,
      const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: EmojiGlyph('p', size: 30),
      ),
    );
    expect(ink.center.dy, closeTo(50, 1));
  });

  testWidgets('measures again when fonts change, as when the web emoji font arrives', (tester) async {
    await renderedInk(tester, const EmojiGlyph('p', size: 40));
    expect(EmojiInk.instance.offsetOf('p'), isNotNull);

    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.system.name,
      SystemChannels.system.codec.encodeMessage({'type': 'fontsChange'}),
      (_) {},
    );
    expect(EmojiInk.instance.offsetOf('p'), isNull); // dropped, and being measured again
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    // The test font's ascent is 0.75em and "p" fills the 0.25em below the
    // baseline, so its middle is 0.375em below the box's.
    expect(EmojiInk.instance.offsetOf('p')!.dy, closeTo(0.375, 0.01));
  });
}
