import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text.dart';
import '../../data/database.dart';
import '../../state/providers.dart';

/// Returns "Merchant" for an expense and "Source" for income.
String merchantLabel(TxKind kind) => kind == TxKind.income ? 'Source' : 'Merchant';

/// Returns the error the merchant field shows when it is blank.
String merchantMissingMessage(TxKind kind) => kind == TxKind.income ? 'Enter a source' : 'Enter a merchant';

/// A text field for the merchant that suggests merchants already used for [kind]. When [categoryId] is set, it only
/// suggests that category's merchants.
///
/// The field keeps its own text controller. [onChanged] receives every change to the text, including a picked
/// suggestion.
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

  /// Decorates the text field. The field replaces any labelText with [merchantLabel].
  final InputDecoration decoration;

  /// The field shows at most this many suggestions at once.
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
    // A suggestion matches when it contains the typed text, ignoring case. A suggestion that equals the typed text,
    // ignoring case and spacing, is the merchant already typed, so the filter leaves it out.
    final q = merchantKey(text);
    return suggestions
        .where((m) {
          final key = merchantKey(m);
          return key != q && key.contains(q);
        })
        .take(MerchantField.maxSuggestions);
  }

  @override
  Widget build(BuildContext context) {
    final suggestions =
        ref.watch(merchantSuggestionsProvider((kind: widget.kind, categoryId: widget.categoryId))).value ??
        const <String>[];

    // RawAutocomplete only calls optionsBuilder again when the text changes. A new suggestion list, from a new category
    // or from data that just loaded, gets a new key, which replaces the RawAutocomplete. The RawAutocomplete sits
    // beside the TextField instead of building it, so replacing it keeps the field's text and focus.
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

/// Notifies listeners without changing the text, so a new RawAutocomplete runs optionsBuilder for the current text.
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
