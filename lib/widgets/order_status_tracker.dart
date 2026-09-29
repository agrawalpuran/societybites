import 'package:flutter/material.dart';

import '../models/order_lifecycle.dart';

class OrderStatusTracker extends StatelessWidget {
  const OrderStatusTracker({
    super.key,
    required this.currentStep,
    required this.steps,
  });

  final int currentStep;
  final List<String> steps;

  static const _circleSize = 28.0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: _circleSize / 2 - 1,
          left: _circleSize / 2,
          right: _circleSize / 2,
          child: Row(
            children: [
              for (var i = 0; i < steps.length - 1; i++)
                Expanded(
                  child: Container(
                    height: 2,
                    color: i < currentStep
                        ? const Color(0xFF0E5A47)
                        : const Color(0xFFD4DBD8),
                  ),
                ),
            ],
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < steps.length; i++)
              Expanded(
                child: _StepColumn(
                  index: i,
                  currentStep: currentStep,
                  label: steps[i],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _StepColumn extends StatelessWidget {
  const _StepColumn({
    required this.index,
    required this.currentStep,
    required this.label,
  });

  final int index;
  final int currentStep;
  final String label;

  @override
  Widget build(BuildContext context) {
    final isActive = index <= currentStep;
    final isCurrent = index == currentStep;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          Container(
            width: OrderStatusTracker._circleSize,
            height: OrderStatusTracker._circleSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive
                  ? const Color(0xFF0E5A47)
                  : const Color(0xFFF0F2F1),
              border: isCurrent
                  ? Border.all(color: const Color(0xFF0E5A47), width: 2)
                  : null,
            ),
            child: isActive
                ? Icon(
                    isCurrent ? Icons.restaurant_rounded : Icons.check_rounded,
                    size: 14,
                    color: Colors.white,
                  )
                : null,
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              BuyerOrderLifecycle.progressStepDisplayLabel(label),
              textAlign: TextAlign.center,
              softWrap: false,
              maxLines: 2,
              style: TextStyle(
                fontSize: 10,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: isActive
                    ? const Color(0xFF0E5A47)
                    : const Color(0xFF8A9491),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
