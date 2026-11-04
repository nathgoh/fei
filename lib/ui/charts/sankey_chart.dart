import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../domain/analytics.dart';
import '../../domain/sankey.dart';

/// Left-to-right Sankey diagram: income → expenses/savings → categories.
///
/// On narrow screens income sources are collapsed into one node and amounts
/// are abbreviated, so the chart fits without horizontal scrolling.
class SankeyChart extends StatelessWidget {
  const SankeyChart({super.key, required this.summary});
  final PeriodSummary summary;

  static const _compactBelow = 560.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < _compactBelow;
        final data = buildCashFlowSankey(summary, collapseSources: compact);
        final perColumn = <int, int>{};
        for (final n in data.nodes) {
          perColumn.update(n.column, (v) => v + 1, ifAbsent: () => 1);
        }
        final maxNodes = perColumn.values.fold(1, math.max);
        return SizedBox(
          width: constraints.maxWidth,
          height: math.max(240.0, maxNodes * 36.0),
          child: CustomPaint(
            painter: _SankeyPainter(
              data,
              compact: compact,
              labelStyle: theme.textTheme.labelSmall!.copyWith(color: theme.colorScheme.onSurface),
              detailStyle: theme.textTheme.labelSmall!.copyWith(color: theme.colorScheme.onSurfaceVariant),
              labelBackground: theme.colorScheme.surfaceContainer.withValues(alpha: 0.85),
              leaderColor: theme.colorScheme.outlineVariant,
            ),
          ),
        );
      },
    );
  }
}

class _Placed {
  _Placed(this.node, this.rect);
  final SankeyNode node;
  final Rect rect;
  double outOffset = 0;
  double inOffset = 0;
}

class _SankeyPainter extends CustomPainter {
  _SankeyPainter(
    this.data, {
    required this.compact,
    required this.labelStyle,
    required this.detailStyle,
    required this.labelBackground,
    required this.leaderColor,
  });
  final SankeyData data;
  final bool compact;
  final TextStyle labelStyle;
  final TextStyle detailStyle;
  final Color labelBackground;
  final Color leaderColor;

  static const nodeWidth = 10.0;
  static const nodeGap = 10.0;
  double get lastLabelWidth => compact ? 104.0 : 160.0;
  double get leaderGap => compact ? 14.0 : 20.0;

  String _amount(int cents) => compact ? formatCompact(cents) : formatMoney(cents);

  TextPainter _label(SankeyNode n, double maxWidth) {
    final detail = n.share == null
        ? _amount(n.value)
        : '${_amount(n.value)} · ${formatPercent(n.share!, digits: compact ? 0 : 1)}';
    return TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: '${n.label}\n',
            style: labelStyle.copyWith(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: detail, style: detailStyle),
        ],
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final columns = data.columns;
    if (columns == 0) return;

    final byColumn = <int, List<SankeyNode>>{};
    for (final n in data.nodes) {
      byColumn.putIfAbsent(n.column, () => []).add(n);
    }

    // One vertical scale for every column so band widths are comparable.
    var scale = double.infinity;
    for (final nodes in byColumn.values) {
      final total = nodes.fold<int>(0, (s, n) => s + n.value);
      if (total == 0) continue;
      scale = math.min(scale, (size.height - nodeGap * (nodes.length - 1)) / total);
    }
    if (!scale.isFinite) return;

    // The last column's labels sit to the right, after a short leader line.
    final usableWidth = size.width - lastLabelWidth - leaderGap - nodeWidth;
    final step = columns == 1 ? 0.0 : usableWidth / (columns - 1);
    final placed = <String, _Placed>{};
    for (final entry in byColumn.entries) {
      final nodes = entry.value;
      final total = nodes.fold<double>(0, (s, n) => s + n.value * scale) + nodeGap * (nodes.length - 1);
      var y = (size.height - total) / 2;
      final x = entry.key * step;
      for (final n in nodes) {
        placed[n.id] = _Placed(n, Rect.fromLTWH(x, y, nodeWidth, math.max(n.value * scale, 2.0)));
        y += n.value * scale + nodeGap;
      }
    }

    // Links first, so nodes and labels sit on top.
    for (final link in data.links) {
      final from = placed[link.from], to = placed[link.to];
      if (from == null || to == null || link.value <= 0) continue;
      final thickness = link.value * scale;
      final x0 = from.rect.right, x1 = to.rect.left;
      final y0 = from.rect.top + from.outOffset;
      final y1 = to.rect.top + to.inOffset;
      from.outOffset += thickness;
      to.inOffset += thickness;
      final mid = (x0 + x1) / 2;
      final path = Path()
        ..moveTo(x0, y0)
        ..cubicTo(mid, y0, mid, y1, x1, y1)
        ..lineTo(x1, y1 + thickness)
        ..cubicTo(mid, y1 + thickness, mid, y0 + thickness, x0, y0 + thickness)
        ..close();
      canvas.drawPath(path, Paint()..color = link.color.withValues(alpha: 0.35));
    }

    for (final p in placed.values) {
      canvas.drawRRect(RRect.fromRectAndRadius(p.rect, const Radius.circular(3)), Paint()..color = p.node.color);
    }

    // Inner columns: label beside the node, over the bands, with a backing.
    for (final p in placed.values.where((p) => p.node.column != columns - 1)) {
      final painter = _label(p.node, math.max(step - nodeWidth - 12, 60));
      final offset = Offset(p.rect.right + 5, p.rect.center.dy - painter.height / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(offset.dx - 3, offset.dy - 2, painter.width + 6, painter.height + 4),
          const Radius.circular(4),
        ),
        Paint()..color = labelBackground,
      );
      painter.paint(canvas, offset);
    }

    // Last column: stack labels so small categories never overlap, and draw a
    // leader line from each node to its label.
    final last = (byColumn[columns - 1] ?? const []).map((n) => placed[n.id]!).toList();
    final labels = [for (final p in last) _label(p.node, lastLabelWidth - 4)];
    final tops = [for (var i = 0; i < last.length; i++) last[i].rect.center.dy - labels[i].height / 2];
    for (var i = 1; i < tops.length; i++) {
      tops[i] = math.max(tops[i], tops[i - 1] + labels[i - 1].height + 2);
    }
    for (var i = tops.length - 1; i >= 0; i--) {
      final limit = i == tops.length - 1 ? size.height - labels[i].height : tops[i + 1] - labels[i].height - 2;
      tops[i] = math.max(0, math.min(tops[i], limit));
    }
    final labelX = size.width - lastLabelWidth;
    final leader = Paint()
      ..color = leaderColor
      ..strokeWidth = 1;
    for (var i = 0; i < last.length; i++) {
      final from = Offset(last[i].rect.right + 2, last[i].rect.center.dy);
      final to = Offset(labelX - 3, tops[i] + labels[i].height / 2);
      canvas.drawLine(from, to, leader);
      labels[i].paint(canvas, Offset(labelX, tops[i]));
    }
  }

  @override
  bool shouldRepaint(covariant _SankeyPainter old) =>
      old.data != data || old.compact != compact || old.labelStyle != labelStyle;
}
