import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:emoji_picker_flutter/locales/default_emoji_set_locale.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

/// Opens a searchable emoji picker in a bottom sheet and returns the chosen
/// emoji, or null if the sheet is dismissed. It's drawn by Flutter, so it
/// works the same on web as on phones.
Future<String?> pickEmoji(BuildContext context) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => const EmojiPickerSheet(),
);

class EmojiPickerSheet extends StatefulWidget {
  const EmojiPickerSheet({super.key});

  @override
  State<EmojiPickerSheet> createState() => _EmojiPickerSheetState();
}

class _EmojiPickerSheetState extends State<EmojiPickerSheet> {
  static const _locale = Locale('en');
  final _utils = EmojiPickerUtils();
  String _query = '';
  List<Emoji> _results = const [];

  /// The tab to open on: recently picked emoji, or smileys until there are
  /// any, so a first-time user doesn't land on an empty tab.
  Category? _startOn;

  @override
  void initState() {
    super.initState();
    _utils.getRecentEmojis().then((recent) {
      if (mounted) setState(() => _startOn = recent.isEmpty ? Category.SMILEYS : Category.RECENT);
    });
  }

  Future<void> _search(String query) async {
    setState(() => _query = query.trim());
    final results = await _utils.searchEmoji(_query, getDefaultEmojiLocale(_locale));
    // Results can arrive out of order, so keep only the latest query's.
    if (mounted && query.trim() == _query) setState(() => _results = results);
  }

  void _choose(Category? _, Emoji emoji) => Navigator.pop(context, emoji.emoji);

  /// The picker records its own picks as recent, but search results are drawn
  /// here, so record those too.
  void _chooseFromSearch(Category? category, Emoji emoji) {
    _utils.addEmojiToRecentlyUsed(key: GlobalKey<EmojiPickerState>(), emoji: emoji);
    _choose(category, emoji);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Matches the sheet's own background, so the picker blends in.
    final background = Theme.of(context).bottomSheetTheme.backgroundColor ?? colors.surfaceContainerLow;
    final screen = MediaQuery.sizeOf(context);
    return Padding(
      // Lifts the sheet above the on-screen keyboard while searching.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: (screen.height * 0.6).clamp(320.0, 460.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final config = Config(
              height: null,
              locale: _locale,
              emojiViewConfig: EmojiViewConfig(
                // About 48px per cell, so phones get 8 columns and the wider web
                // sheet gets more without the emoji growing huge.
                columns: (constraints.maxWidth / 48).floor().clamp(6, 14),
                emojiSizeMax: 28,
                backgroundColor: background,
                noRecents: Text(
                  'Emoji you pick show up here',
                  style: context.text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ),
              categoryViewConfig: CategoryViewConfig(
                initCategory: _startOn ?? Category.RECENT,
                backgroundColor: background,
                indicatorColor: colors.primary,
                iconColor: colors.onSurfaceVariant,
                iconColorSelected: colors.primary,
                dividerColor: colors.outlineVariant,
              ),
              skinToneConfig: SkinToneConfig(dialogBackgroundColor: colors.surfaceContainerHigh),
              // The search field sits above the picker instead, like the
              // category picker's.
              bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
            );
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    decoration: const InputDecoration(hintText: 'Search emoji', prefixIcon: Icon(Icons.search)),
                    onChanged: _search,
                  ),
                ),
                Expanded(
                  child: _query.isNotEmpty
                      ? _SearchResults(results: _results, config: config, onSelected: _chooseFromSearch)
                      : _startOn == null
                      ? const SizedBox.shrink()
                      : EmojiPicker(config: config, onEmojiSelected: _choose),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.results, required this.config, required this.onSelected});
  final List<Emoji> results;
  final Config config;
  final OnEmojiSelected onSelected;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return Center(
        child: Text(
          'No matching emoji',
          style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final view = config.emojiViewConfig;
        return GridView.count(
          crossAxisCount: view.columns,
          children: [
            for (final e in results)
              EmojiCell.fromConfig(
                emoji: e,
                emojiSize: view.getEmojiSize(constraints.maxWidth),
                emojiBoxSize: view.getEmojiBoxSize(constraints.maxWidth),
                onEmojiSelected: onSelected,
                config: config,
              ),
          ],
        );
      },
    );
  }
}
