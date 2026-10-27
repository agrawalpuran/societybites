import 'package:flutter/material.dart';

/// Stops [InkWell] / parent [GestureDetector] on listing cards from opening
/// detail when the buyer taps Add or +/-.
class ListingCartTapShield extends StatelessWidget {
  const ListingCartTapShield({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: child,
    );
  }
}

class ListingCartAddButton extends StatelessWidget {
  const ListingCartAddButton({
    super.key,
    required this.onPressed,
    this.compact = false,
    this.optionsLabel,
  });

  final VoidCallback onPressed;
  final bool compact;

  /// Blinkit-style line under Add, e.g. "2 options".
  final String? optionsLabel;

  @override
  Widget build(BuildContext context) {
    final radius = compact ? 10.0 : 12.0;
    final hasOptions =
        optionsLabel != null && optionsLabel!.trim().isNotEmpty;
    // Keep multi-option Add close to single-SKU size so mobile cards stay balanced.
    final hPad = hasOptions
        ? (compact ? 10.0 : 11.0)
        : (compact ? 12.0 : 14.0);
    final vPad = hasOptions
        ? (compact ? 4.0 : 4.5)
        : (compact ? 6.0 : 7.0);
    return ListingCartTapShield(
      child: Material(
        color: const Color(0xFF0E5A47),
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(radius),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
            child: hasOptions
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Add',
                        softWrap: false,
                        maxLines: 1,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: compact ? 12 : 13,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                        ),
                      ),
                      Text(
                        optionsLabel!,
                        softWrap: false,
                        maxLines: 1,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: compact ? 8 : 8.5,
                          fontWeight: FontWeight.w500,
                          height: 1.05,
                        ),
                      ),
                    ],
                  )
                : const Text(
                    'Add',
                    softWrap: false,
                    maxLines: 1,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class ListingCartQtyStepper extends StatelessWidget {
  const ListingCartQtyStepper({
    super.key,
    required this.qty,
    required this.onIncrement,
    required this.onDecrement,
    this.compact = false,
  });

  final int qty;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final radius = compact ? 10.0 : 12.0;
    final iconSize = compact ? 16.0 : 18.0;
    final fontSize = compact ? 13.0 : 14.0;
    return ListingCartTapShield(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF0E5A47),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const Key('listing-cart-decrement'),
              onPressed: onDecrement,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: BoxConstraints.tightFor(
                width: compact ? 28 : 32,
                height: compact ? 28 : 32,
              ),
              icon: Icon(Icons.remove, size: iconSize, color: Colors.white),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '$qty',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              key: const Key('listing-cart-increment'),
              onPressed: onIncrement,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: BoxConstraints.tightFor(
                width: compact ? 28 : 32,
                height: compact ? 28 : 32,
              ),
              icon: Icon(Icons.add, size: iconSize, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
