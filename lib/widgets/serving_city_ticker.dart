import 'package:flutter/material.dart';

/// Horizontally scrolling label for compact headers (e.g. "Now serving Bengaluru").
class ServingCityTicker extends StatefulWidget {
  const ServingCityTicker({
    super.key,
    required this.text,
    this.style,
    this.gap = 28,
    this.pixelsPerSecond = 28,
    this.alwaysAnimate = true,
  });

  final String text;
  final TextStyle? style;
  final double gap;
  final double pixelsPerSecond;

  /// When true, scrolls even if the label fits (subtle ticker on wide layouts).
  final bool alwaysAnimate;

  @override
  State<ServingCityTicker> createState() => _ServingCityTickerState();
}

class _ServingCityTickerState extends State<ServingCityTicker>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  double _segmentWidth = 0;

  static const _defaultStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: Color(0xFF0E5A47),
  );

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _syncAnimation(double segmentWidth) {
    if (segmentWidth <= 0) return;
    if (_segmentWidth == segmentWidth && _controller != null) return;
    _segmentWidth = segmentWidth;
    _controller?.dispose();
    final ms = (segmentWidth / widget.pixelsPerSecond * 1000).round().clamp(
      4000,
      20000,
    );
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: ms),
    )..repeat();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? _defaultStyle;
    if (MediaQuery.disableAnimationsOf(context)) {
      return Text(
        widget.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        final textWidth = painter.width;
        final segmentWidth = textWidth + widget.gap;

        if (!maxWidth.isFinite || maxWidth <= 0 || textWidth <= 0) {
          return Text(widget.text, maxLines: 1, style: style);
        }

        if (!widget.alwaysAnimate && textWidth <= maxWidth + 1) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Text(widget.text, maxLines: 1, style: style),
          );
        }

        _syncAnimation(segmentWidth);
        final controller = _controller!;
        final lineHeight = (style.fontSize ?? 11) * (style.height ?? 1.2);
        return SizedBox(
          width: maxWidth,
          height: lineHeight,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, child) {
                return OverflowBox(
                  alignment: Alignment.centerLeft,
                  maxWidth: segmentWidth * 2,
                  minWidth: segmentWidth * 2,
                  maxHeight: lineHeight,
                  minHeight: lineHeight,
                  child: Transform.translate(
                    offset: Offset(-controller.value * segmentWidth, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.text, maxLines: 1, style: style),
                        SizedBox(width: widget.gap),
                        Text(widget.text, maxLines: 1, style: style),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
