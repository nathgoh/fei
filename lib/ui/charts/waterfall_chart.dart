import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../domain/analytics.dart';
import '../../domain/waterfall.dart';
import '../theme.dart';
import '../widgets.dart';

/// Vertical money flow for a period: income, then expenses, then what's left.
///
/// Income and expenses are stacked bars (by source and by category) that
/// expand to show each part. The expense bar always fills its track; income
/// and savings share one axis, so savings show how much of income is left.
class CashFlowWaterfallChart extends StatefulWidget {
  const CashFlowWaterfallChart({super.key, required this.summary});
  final PeriodSummary summary;

  @override
  State<CashFlowWaterfallChart> createState() => _CashFlowWaterfallChartState();
}

class _CashFlowWaterfallChartState extends State<CashFlowWaterfallChart> {
  bool _incomeOpen = false;
  bool _expensesOpen = false;

  @override
  Widget build(BuildContext context) {
    final w = CashFlowWaterfall.of(widget.summary);
    if (w.isEmpty) return const SizedBox.shrink();
    final muted = context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (w.hasIncome)
          _FlowGroup(
            key: const ValueKey('flow-income'),
            icon: Icons.account_balance_wallet_outlined,
            title: 'Income',
            cents: w.incomeCents,
            amountColor: context.incomeColor,
            caption: w.sources.length > 1 ? '${w.sources.length} sources' : null,
            span: w.income,
            total: w.total,
            parts: w.sources,
            partsTitle: 'Income sources',
            open: _incomeOpen,
            onToggle: () => setState(() => _incomeOpen = !_incomeOpen),
          ),
        if (w.hasIncome && w.hasExpenses)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [Icon(Icons.arrow_downward, size: 14, color: context.colors.onSurfaceVariant)],
            ),
          ),
        if (w.hasExpenses)
          _FlowGroup(
            key: const ValueKey('flow-expenses'),
            icon: Icons.receipt_long_outlined,
            title: 'Expenses',
            cents: w.expenseCents,
            caption: w.spentShare == null ? null : '${formatPercent(w.spentShare!)} of income',
            span: (start: 0, end: w.expenseCents),
            total: w.expenseCents,
            parts: w.categories,
            partsTitle: 'Expense categories',
            open: _expensesOpen,
            onToggle: () => setState(() => _expensesOpen = !_expensesOpen),
          ),
        if (w.hasIncome) ...[const SizedBox(height: 16), _SavingsRow(waterfall: w)],
      ],
    );
  }
}

/// An outlined, expandable block: icon + title, a big amount, a stacked bar,
/// and (when open) one row per part.
class _FlowGroup extends StatelessWidget {
  const _FlowGroup({
    super.key,
    required this.icon,
    required this.title,
    required this.cents,
    required this.span,
    required this.total,
    required this.parts,
    required this.partsTitle,
    required this.open,
    required this.onToggle,
    this.caption,
    this.amountColor,
  });
  final IconData icon;
  final String title;
  final int cents;
  final String? caption;
  final Color? amountColor;
  final Span span;
  final int total;
  final List<CategoryTotal> parts;
  final String partsTitle;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.onSurfaceVariant;
    final radius = BorderRadius.circular(14);
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: context.colors.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 18, color: muted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      ),
                      Semantics(
                        label: open ? 'Collapse $title' : 'Expand $title',
                        child: AnimatedRotation(
                          turns: open ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(Icons.expand_more, color: muted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(
                            formatMoney(cents),
                            style: context.text.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: amountColor,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        if (caption != null) Text(caption!, style: context.text.bodySmall?.copyWith(color: muted)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _AxisBar(
                      span: span,
                      total: total,
                      height: 12,
                      segments: [for (final p in parts) (cents: p.cents, color: Color(p.category.color))],
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Divider(height: 1, color: context.colors.outlineVariant.withValues(alpha: 0.5)),
                        const SizedBox(height: 12),
                        Text(
                          partsTitle.toUpperCase(),
                          style: context.text.labelSmall?.copyWith(color: muted, letterSpacing: 0.8),
                        ),
                        const SizedBox(height: 4),
                        for (final p in parts) _PartRow(part: p),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// A source or category: icon, name, amount, and its share of the group.
class _PartRow extends StatelessWidget {
  const _PartRow({required this.part});
  final CategoryTotal part;

  @override
  Widget build(BuildContext context) {
    final color = Color(part.category.color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CategoryAvatar(part.category, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(part.category.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    Text(
                      formatPercent(part.share, digits: 0),
                      style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                    const SizedBox(width: 8),
                    Text(formatMoney(part.cents), style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
                  ],
                ),
                const SizedBox(height: 6),
                _AxisBar(
                  span: (start: 0, end: (part.share * 100).round()),
                  total: 10000,
                  height: 5,
                  segments: [(cents: 1, color: color)],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What's left after expenses: blue and positive, or red and negative when
/// spending exceeds income.
class _SavingsRow extends StatelessWidget {
  const _SavingsRow({required this.waterfall});
  final CashFlowWaterfall waterfall;

  @override
  Widget build(BuildContext context) {
    final w = waterfall;
    final color = w.isDeficit ? context.negativeColor : context.savingsColor;
    final muted = context.colors.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(w.isDeficit ? Icons.trending_down : Icons.savings_outlined, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Savings', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (w.savingsRate != null) ...[
                Text(formatPercent(w.savingsRate!), style: context.text.bodySmall?.copyWith(color: muted)),
                const SizedBox(width: 10),
              ],
              Text(
                formatMoney(w.savingsCents),
                style: context.text.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          if (w.savingsCents != 0) ...[
            const SizedBox(height: 8),
            _AxisBar(span: w.savings, total: w.total, height: 12, segments: [(cents: 1, color: color)]),
          ],
        ],
      ),
    );
  }
}

typedef _Segment = ({int cents, Color color});

/// A rounded bar covering [span] of a 0..[total] track, split into
/// [segments] in proportion to their cents.
class _AxisBar extends StatelessWidget {
  const _AxisBar({required this.span, required this.total, required this.segments, required this.height});
  final Span span;
  final int total;
  final List<_Segment> segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _AxisBarPainter(
          span: span,
          total: total,
          segments: segments,
          track: context.colors.surfaceContainerHighest.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

class _AxisBarPainter extends CustomPainter {
  _AxisBarPainter({required this.span, required this.total, required this.segments, required this.track});
  final Span span;
  final int total;
  final List<_Segment> segments;
  final Color track;

  static const _gap = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, radius), Paint()..color = track);
    if (total <= 0 || span.end <= span.start) return;

    // Keep tiny bars visible without spilling off the track.
    final minWidth = math.min(size.height, size.width);
    final width = math.max((span.end - span.start) / total * size.width, minWidth);
    final left = math.min(span.start / total * size.width, size.width - width);
    final bar = Rect.fromLTWH(left, 0, width, size.height);

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(bar, radius));
    final sum = segments.fold<int>(0, (a, s) => a + s.cents);
    var x = bar.left;
    for (final (i, s) in segments.indexed) {
      final w = sum == 0 ? 0.0 : s.cents / sum * bar.width;
      final last = i == segments.length - 1;
      // Gaps only between segments wide enough to keep some color.
      final gap = !last && w > _gap * 2 ? _gap : 0.0;
      canvas.drawRect(Rect.fromLTWH(x, 0, math.max(w - gap, 0), size.height), Paint()..color = s.color);
      x += w;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AxisBarPainter old) =>
      old.span != span || old.total != total || old.track != track || !_sameSegments(old.segments, segments);

  static bool _sameSegments(List<_Segment> a, List<_Segment> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
