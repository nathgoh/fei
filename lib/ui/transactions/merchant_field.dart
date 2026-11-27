import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text.dart';
import '../../data/database.dart';
import '../../state/providers.dart';

/// "Merchant" for spending, "Source" for income.
String merchantLabel(TxKind kind) => kind == TxKind.income ? 'Source' : 'Merchant';

/// The error shown when the merchant field is left blank.
String merchantMissingMessage(TxKind kind) => kind == TxKind.income ? 'Enter a source' : 'Enter a merchant';

/// A merchant text field that suggests merchants already used for [kind],
/// limited to [categoryId] when one is picked.
///
/// The field owns its text; [onChanged] reports every change, including a
/// picked suggestion.
class MerchantField extends ConsumerStatefulWidget {
  const MerchantField({
    super.key,
    required this.kind,
    required this.categoryId,
    required this.initialValue,
    required this.onChanged,
    required this.decoration,
  });

  final TxKind kind;
  final String? categoryId;
  final String initialValue;
  final ValueChanged<String> onChanged;

  /// Decoration for the text field. The label comes from [merchantLabel].
  final InputDecoration decoration;

  /// The most suggestions shown at once.
  static const maxSuggestions = 8;

  @override
  ConsumerState<MerchantField> createState() => _MerchantFieldState();
}

class _MerchantFieldState extends ConsumerState<MerchantField> {
  late final _controller = _RefreshableController(text: widget.initialValue);
  final _focus = FocusNode(debugLabel: 'merchant');
  String _lastText = '';
  ValueKey<String>? _autocompleteKey;

  @override
  void initState() {
    super.initState();
    _lastText = _controller.text;
    _controller.addListener(_onText);
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onText() {
    if (_controller.text == _lastText) return;
    _lastText = _controller.text;
    widget.onChanged(_lastText);
  }

  void _onFocus() {
    if (_focus.hasFocus) _controller.refresh();
  }

  Iterable<String> _options(List<String> suggestions, String text) {
    // Saving normalizes the name, so a suggestion matching the typed text in
    // all but case and spacing adds nothing.
    final q = normalizeMerchant(text).toLowerCase();
    return suggestions
        .where((m) => m.toLowerCase() != q && m.toLowerCase().contains(q))
        .take(MerchantField.maxSuggestions);
  }

  @override
  Widget build(BuildContext context) {
    final suggestions =
        ref.watch(merchantSuggestionsProvider((kind: widget.kind, categoryId: widget.categoryId))).value ??
        const <String>[];

    // RawAutocomplete only re-runs optionsBuilder when the text changes, so a
    // new suggestion list (another category, or data that just loaded) gets a
    // fresh RawAutocomplete. It sits beside the TextField rather than building
    // it, so replacing it leaves the field and its focus alone.
    final key = ValueKey(suggestions.join('\u0000'));
    if (key != _autocompleteKey) {
      _autocompleteKey = key;
      if (_focus.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _controller.refresh();
        });
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focus,
          textCapitalization: TextCapitalization.words,
          decoration: widget.decoration.copyWith(labelText: merchantLabel(widget.kind)),
        ),
        RawAutocomplete<String>(
          key: key,
          textEditingController: _controller,
          focusNode: _focus,
          optionsBuilder: (value) => _options(suggestions, value.text),
          optionsViewBuilder: (context, onSelected, options) => _SuggestionList(options, onSelected),
        ),
      ],
    );
  }
}

/// Lets [MerchantField] ask its RawAutocomplete to re-run its options without
/// changing the text.
class _RefreshableController extends TextEditingController {
  _RefreshableController({super.text});

  void refresh() => notifyListeners();
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList(this.options, this.onSelected);
  final Iterable<String> options;
  final AutocompleteOnSelected<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.topStart,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: ListView(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            children: [
              for (final m in options)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.history, size: 20),
                  title: Text(m),
                  onTap: () => onSelected(m),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
