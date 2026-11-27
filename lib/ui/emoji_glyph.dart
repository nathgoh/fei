import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Draws an emoji so its visible artwork, not its text box, sits in the
/// middle of the space it's given.
///
/// Emoji fonts don't center their artwork in the em box. In Noto Color Emoji,
/// which web and Android use, the car 🚗 is drawn about a fifth of an em below
/// the middle, and ☕ and 💻 sit low too. Text layout can't see the artwork, so
/// [EmojiInk] draws each emoji once off screen, finds where its pixels are, and
/// this widget shifts the glyph by that amount.
class EmojiGlyph extends StatelessWidget {
  const EmojiGlyph(this.emoji, {super.key, required this.size});
  final String emoji;

  /// The font size, before the user's text scaling.
  final double size;

  @override
  Widget build(BuildContext context) {
    final scaled = MediaQuery.textScalerOf(context).scale(size);
    return ListenableBuilder(
      listenable: EmojiInk.instance,
      builder: (context, child) {
        final offset = EmojiInk.instance.offsetOf(emoji);
        return Transform.translate(offset: offset == null ? Offset.zero : -offset * scaled, child: child);
      },
      child: Text(
        emoji,
        textAlign: TextAlign.center,
        // Not inherited, so the on-screen layout matches the off-screen one
        // that was measured.
        style: emojiTextStyle(size).copyWith(color: DefaultTextStyle.of(context).style.color),
      ),
    );
  }
}

/// The text style emoji are drawn and measured with. A fixed line height
/// keeps the box the same for every glyph, whichever font it comes from.
TextStyle emojiTextStyle(double size) => TextStyle(inherit: false, fontSize: size, height: 1);

/// Measures and caches how far each emoji's artwork sits from the center of
/// its text box, as a fraction of the font size.
class EmojiInk extends ChangeNotifier {
  EmojiInk._() {
    // On web the emoji font downloads after the first frame, and anything
    // measured before then was drawn with a placeholder, so measure again.
    PaintingBinding.instance.systemFonts.addListener(_fontsChanged);
  }

  static final instance = EmojiInk._();

  static const _measureSize = 100.0;

  final _offsets = <String, Offset?>{};
  final _measuring = <String>{};
  var _generation = 0;
  var _notifyScheduled = false;

  /// The cached offset for [emoji], or null while it's being measured or if
  /// it draws nothing. The first call starts the measurement, and listeners
  /// hear when it's done.
  Offset? offsetOf(String emoji) {
    if (_offsets.containsKey(emoji)) return _offsets[emoji];
    if (_measuring.add(emoji)) _measure(emoji, _generation);
    return null;
  }

  Future<void> _measure(String emoji, int generation) async {
    Offset? offset;
    try {
      offset = await _measureInk(emoji);
    } catch (_) {
      offset = null; // a failed measurement just leaves the glyph unshifted
    }
    if (generation != _generation) return; // fonts changed while measuring
    _measuring.remove(emoji);
    _offsets[emoji] = offset;
    if (offset != null && !_notifyScheduled) {
      _notifyScheduled = true;
      scheduleMicrotask(() {
        _notifyScheduled = false;
        notifyListeners();
      });
    }
  }

  void _fontsChanged() {
    _generation++;
    _offsets.clear();
    _measuring.clear();
    notifyListeners();
  }

  static Future<Offset?> _measureInk(String emoji) async {
    final painter = TextPainter(
      text: TextSpan(
        text: emoji,
        style: emojiTextStyle(_measureSize).copyWith(color: const Color(0xFF000000)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Leave room around the box, because emoji artwork often spills past a
    // line height of 1.
    const pad = _measureSize / 2;
    final width = (painter.width + 2 * pad).ceil();
    final height = (painter.height + 2 * pad).ceil();
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Offset(pad, pad));
    final box = Offset(pad, pad) & painter.size;
    painter.dispose();
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    final bytes = await image.toByteData();
    image.dispose();
    if (bytes == null) return null;
    final ink = inkBounds(bytes.buffer.asUint8List(), width, height);
    if (ink == null) return null;
    return (ink.center - box.center) / _measureSize;
  }
}

/// The smallest rectangle holding every pixel of an RGBA image whose alpha
/// is above [threshold], or null if there are none. The threshold skips the
/// faint edge pixels left by anti-aliasing.
@visibleForTesting
Rect? inkBounds(Uint8List rgba, int width, int height, {int threshold = 24}) {
  var left = width, top = height, right = -1, bottom = -1;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (rgba[(y * width + x) * 4 + 3] <= threshold) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  if (right < 0) return null;
  return Rect.fromLTRB(left.toDouble(), top.toDouble(), right + 1.0, bottom + 1.0);
}
