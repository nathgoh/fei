import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../state/appearance.dart';
import '../theme.dart';
import '../widgets.dart';

class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final look = ref.watch(appearanceProvider);
    final notifier = ref.read(appearanceProvider.notifier);
    final isPreset = accentPresets.values.any((c) => c.toARGB32() == look.accent.toARGB32());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Appearance'),
        actions: [TextButton(onPressed: notifier.reset, child: const Text('Reset'))],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _Preview(),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Accent colour',
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final e in accentPresets.entries)
                      _Swatch(
                        color: e.value,
                        label: e.key,
                        selected: e.value.toARGB32() == look.accent.toARGB32(),
                        onTap: () => notifier.setAccent(e.value),
                      ),
                    _Swatch(
                      color: isPreset ? null : look.accent,
                      label: 'Custom',
                      selected: !isPreset,
                      onTap: () async {
                        final picked = await showDialog<Color>(
                          context: context,
                          builder: (_) => ColorPickerDialog(initial: look.accent),
                        );
                        if (picked != null) await notifier.setAccent(picked);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Background',
                child: Column(
                  children: [
                    for (final b in BackgroundStyle.values)
                      _BackgroundOption(
                        style: b,
                        accent: look.accent,
                        selected: look.background == b,
                        onTap: () => notifier.setBackground(b),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A miniature of the dashboard using the live theme.
class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Preview', style: context.text.labelMedium?.copyWith(color: c.onSurfaceVariant)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _figure(context, 'Income', formatMoney(825000), incomeGreen)),
                Expanded(child: _figure(context, 'Expenses', formatMoney(361412), null)),
                Expanded(child: _figure(context, 'Saved', formatMoney(463588), null)),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: 0.56, minHeight: 8, backgroundColor: c.surfaceContainerHighest),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton(onPressed: () {}, child: const Text('Add')),
                FilledButton.tonal(onPressed: () {}, child: const Text('Tonal')),
                const FilterChip(label: Text('Selected'), selected: true, onSelected: _noop),
                Switch(value: true, onChanged: (_) {}),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static void _noop(bool _) {}

  Widget _figure(BuildContext context, String label, String value, Color? color) => Column(
    children: [
      Text(label, style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant)),
      FittedBox(
        child: Text(
          value,
          style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
        ),
      ),
    ],
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.label, required this.selected, required this.onTap});

  /// Null shows a rainbow (custom colour not chosen yet).
  final Color? color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label accent',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 60,
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  gradient: color == null ? const SweepGradient(colors: _hueStops) : null,
                  border: Border.all(color: selected ? context.colors.onSurface : Colors.transparent, width: 3),
                ),
                child: selected ? Icon(Icons.check, color: _onColor(color ?? Colors.white)) : null,
              ),
              const SizedBox(height: 4),
              Text(label, style: context.text.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

Color _onColor(Color c) => ThemeData.estimateBrightnessForColor(c) == Brightness.dark ? Colors.white : Colors.black;

class _BackgroundOption extends StatelessWidget {
  const _BackgroundOption({required this.style, required this.accent, required this.selected, required this.onTap});
  final BackgroundStyle style;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = buildColorScheme(accent: accent, background: style);
    final description = switch (style) {
      BackgroundStyle.tinted => 'Dark surfaces with a hint of your accent colour',
      BackgroundStyle.neutral => 'Plain dark greys',
      BackgroundStyle.black => 'True black, which saves battery on OLED screens',
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Container(
        width: 48,
        height: 48,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.colors.outlineVariant),
        ),
        child: Container(
          decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(6)),
        ),
      ),
      title: Text(backgroundLabel(style)),
      subtitle: Text(description),
      trailing: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? context.colors.primary : context.colors.onSurfaceVariant,
      ),
    );
  }
}

const _hueStops = [
  Color(0xFFFF0000),
  Color(0xFFFFFF00),
  Color(0xFF00FF00),
  Color(0xFF00FFFF),
  Color(0xFF0000FF),
  Color(0xFFFF00FF),
  Color(0xFFFF0000),
];

/// Hue / saturation / brightness sliders plus a hex field.
class ColorPickerDialog extends StatefulWidget {
  const ColorPickerDialog({super.key, required this.initial});
  final Color initial;

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final _hex = TextEditingController(text: _toHex(widget.initial));

  Color get _color => _hsv.toColor();

  static String _toHex(Color c) => (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _update(HSVColor hsv) => setState(() {
    _hsv = hsv;
    _hex.text = _toHex(hsv.toColor());
  });

  @override
  Widget build(BuildContext context) {
    final scheme = buildColorScheme(accent: _color);
    return AlertDialog(
      title: const Text('Custom colour'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: _color, borderRadius: BorderRadius.circular(12)),
                ),
                const SizedBox(width: 12),
                // How the generated palette will look with this colour.
                for (final c in [scheme.primary, scheme.primaryContainer, scheme.secondary, scheme.tertiary])
                  Container(
                    width: 24,
                    height: 24,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hex,
              decoration: const InputDecoration(labelText: 'Hex', prefixText: '#', isDense: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
                LengthLimitingTextInputFormatter(6),
              ],
              onChanged: (v) {
                if (v.length == 6) {
                  setState(() => _hsv = HSVColor.fromColor(Color(0xFF000000 | int.parse(v, radix: 16))));
                }
              },
            ),
            const SizedBox(height: 16),
            _GradientSlider(
              label: 'Hue',
              value: _hsv.hue,
              max: 360,
              colors: _hueStops,
              onChanged: (v) => _update(_hsv.withHue(v)),
            ),
            _GradientSlider(
              label: 'Saturation',
              value: _hsv.saturation,
              colors: [_hsv.withSaturation(0).toColor(), _hsv.withSaturation(1).toColor()],
              onChanged: (v) => _update(_hsv.withSaturation(v)),
            ),
            _GradientSlider(
              label: 'Brightness',
              value: _hsv.value,
              colors: [Colors.black, _hsv.withValue(1).toColor()],
              onChanged: (v) => _update(_hsv.withValue(v)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _color), child: const Text('Use colour')),
      ],
    );
  }
}

class _GradientSlider extends StatelessWidget {
  const _GradientSlider({
    required this.label,
    required this.value,
    required this.colors,
    required this.onChanged,
    this.max = 1,
  });
  final String label;
  final double value;
  final double max;
  final List<Color> colors;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.text.labelMedium),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 12,
            trackShape: _GradientTrack(colors),
            thumbColor: Colors.white,
            overlayColor: Colors.white24,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
          ),
          child: Slider(
            // The 2023 design draws a round thumb on a full-width track,
            // which suits a gradient.
            // ignore: deprecated_member_use
            year2023: true,
            value: value.clamp(0, max),
            max: max,
            semanticFormatterCallback: (v) => '$label ${(v / max * 100).round()}%',
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _GradientTrack extends RoundedRectSliderTrackShape {
  const _GradientTrack(this.colors);
  final List<Color> colors;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)),
      Paint()..shader = LinearGradient(colors: colors).createShader(rect),
    );
  }
}
