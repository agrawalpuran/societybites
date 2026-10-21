import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// MMT-style distance bar: filled track animates as the thumb moves.
class SellingReachRadiusSlider extends StatefulWidget {
  const SellingReachRadiusSlider({
    super.key,
    required this.value,
    required this.minKm,
    required this.maxKm,
    required this.onChanged,
  });

  final int value;
  final int minKm;
  final int maxKm;
  final ValueChanged<int> onChanged;

  static const green = Color(0xFF0E5A47);
  static const track = Color(0xFFE4E9E7);

  @override
  State<SellingReachRadiusSlider> createState() =>
      _SellingReachRadiusSliderState();
}

class _SellingReachRadiusSliderState extends State<SellingReachRadiusSlider> {
  static const _green = SellingReachRadiusSlider.green;
  static const _track = SellingReachRadiusSlider.track;

  double _dragFraction = 0;

  @override
  void initState() {
    super.initState();
    _dragFraction = _fractionFor(widget.value);
  }

  @override
  void didUpdateWidget(covariant SellingReachRadiusSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value ||
        oldWidget.minKm != widget.minKm ||
        oldWidget.maxKm != widget.maxKm) {
      _dragFraction = _fractionFor(widget.value);
    }
  }

  double _fractionFor(int km) {
    final span = (widget.maxKm - widget.minKm).clamp(1, 100);
    return ((km - widget.minKm) / span).clamp(0.0, 1.0);
  }

  int _kmForFraction(double fraction) {
    final span = widget.maxKm - widget.minKm;
    return (widget.minKm + fraction * span).round().clamp(widget.minKm, widget.maxKm);
  }

  @override
  Widget build(BuildContext context) {
    final km = _kmForFraction(_dragFraction);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${widget.minKm} km',
              style: const TextStyle(fontSize: 12, color: Color(0xFF6A7774)),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween(end: km.toDouble()),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              builder: (context, animatedKm, child) {
                return Text(
                  '${animatedKm.round()} km',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _green,
                  ),
                );
              },
            ),
            Text(
              '${widget.maxKm} km',
              style: const TextStyle(fontSize: 12, color: Color(0xFF6A7774)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            const thumbSize = 28.0;
            final width = constraints.maxWidth;
            final travel = (width - thumbSize).clamp(1.0, double.infinity);
            return GestureDetector(
              onHorizontalDragUpdate: (details) {
                final local = (details.localPosition.dx - thumbSize / 2) / travel;
                setState(() => _dragFraction = local.clamp(0.0, 1.0));
              },
              onHorizontalDragEnd: (_) {
                final next = _kmForFraction(_dragFraction);
                HapticFeedback.selectionClick();
                widget.onChanged(next);
                setState(() => _dragFraction = _fractionFor(next));
              },
              onTapDown: (details) {
                final local = (details.localPosition.dx - thumbSize / 2) / travel;
                final next = _kmForFraction(local.clamp(0.0, 1.0));
                HapticFeedback.selectionClick();
                widget.onChanged(next);
                setState(() => _dragFraction = _fractionFor(next));
              },
              child: SizedBox(
                height: 44,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: _track,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      height: 6,
                      width: thumbSize / 2 + travel * _dragFraction,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF0E5A47),
                            Color(0xFF1A7A62),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      left: travel * _dragFraction,
                      child: Container(
                        width: thumbSize,
                        height: thumbSize,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _green,
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        const Text(
          'Drag to choose how far buyers can discover your kitchen',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Color(0xFF6A7774)),
        ),
      ],
    );
  }
}
