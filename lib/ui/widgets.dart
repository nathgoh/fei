import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../data/database.dart';
import 'theme.dart';

class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar(this.category, {super.key, this.size = 40});
  final Category? category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = category == null ? context.colors.outline : Color(category!.color);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.22), shape: BoxShape.circle),
      child: Text(category?.emoji ?? '❔', style: TextStyle(fontSize: size * 0.45)),
    );
  }
}

/// An amount coloured by direction: income green with a `+`, expenses plain.
class AmountText extends StatelessWidget {
  const AmountText(this.cents, this.kind, {super.key, this.style});
  final int cents;
  final TxKind kind;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final isIncome = kind == TxKind.income;
    return Text(
      isIncome ? '+${formatMoney(cents)}' : formatMoney(cents),
      style: (style ?? context.text.bodyLarge)?.copyWith(
        color: isIncome ? incomeGreen : null,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 16),
  });
  final String title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                ),
                ?trailing,
              ],
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.caption, this.valueColor});
  final String label;
  final String value;
  final String? caption;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: context.text.labelLarge?.copyWith(color: context.colors.onSurfaceVariant)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: context.text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: valueColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            if (caption != null) ...[
              const SizedBox(height: 2),
              Text(caption!, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Lays out [children] in a responsive grid of equal-width tiles.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children, this.minTileWidth = 160, this.spacing = 12});
  final List<Widget> children;
  final double minTileWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / minTileWidth).floor().clamp(1, children.length);
        final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [for (final c in children) SizedBox(width: width, child: c)],
        );
      },
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: context.colors.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: context.text.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// `‹ November 2026 ›`
class PeriodSwitcher extends StatelessWidget {
  const PeriodSwitcher({super.key, required this.label, this.onPrevious, this.onNext, this.onTap});
  final String label;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(onPressed: onPrevious, icon: const Icon(Icons.chevron_left), tooltip: 'Previous'),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(label, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ),
        IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right), tooltip: 'Next'),
      ],
    );
  }
}

class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Settings',
    icon: const Icon(Icons.settings_outlined),
    onPressed: () => context.push('/settings'),
  );
}

/// Constrains page content on wide screens and adds standard padding.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.maxWidth = 1100});
  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 16), children[i]],
          ],
        ),
      ),
    );
  }
}

/// Renders an [AsyncValue], showing a spinner or error as needed.
class AsyncView<T> extends StatelessWidget {
  const AsyncView(this.value, {super.key, required this.builder});
  final AsyncValue<T> value;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EmptyState(icon: Icons.error_outline, title: 'Something went wrong', message: '$e'),
    );
  }
}

/// A one-line transaction row used across screens.
class TransactionTile extends ConsumerWidget {
  const TransactionTile({
    super.key,
    required this.txn,
    required this.category,
    this.accountName,
    this.onTap,
    this.showDate = false,
  });
  final Txn txn;
  final Category? category;
  final String? accountName;
  final VoidCallback? onTap;
  final bool showDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = txn.merchant ?? txn.notes ?? category?.name ?? 'Uncategorized';
    final subtitle = [
      if (showDate) formatDateShort(parseYmd(txn.date)),
      if (title != category?.name) category?.name ?? 'Uncategorized',
      ?accountName,
    ].join(' · ');
    return ListTile(
      onTap: onTap,
      leading: CategoryAvatar(category),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isEmpty
          ? null
          : Row(
              children: [
                if (txn.recurringId != null) ...[
                  Icon(Icons.repeat, size: 14, color: context.colors.onSurfaceVariant),
                  const SizedBox(width: 4),
                ],
                Flexible(child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
      trailing: AmountText(txn.amountCents, txn.kind),
    );
  }
}

void showMessage(BuildContext context, String message, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action, behavior: SnackBarBehavior.floating));
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: context.colors.error, foregroundColor: context.colors.onError)
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
