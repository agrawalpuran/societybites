import 'package:flutter/material.dart';

import '../models/data.dart';
import 'temporarily_unavailable_label.dart';

/// Buyer-facing purchase control. Expired listings stay visible without Add.
class MarketplacePurchaseSlot extends StatelessWidget {
  const MarketplacePurchaseSlot({
    super.key,
    required this.food,
    required this.cartQty,
    required this.addButton,
    required this.qtyStepper,
    required this.soldOut,
    this.compact = true,
  });

  final FoodItem food;
  final int cartQty;
  final Widget addButton;
  final Widget qtyStepper;
  final Widget soldOut;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Recurring closed copy lives on RecurringAvailabilityHint, not the Add slot.
    if (food.recurringUnavailable) {
      return const SizedBox.shrink();
    }
    final stockLabel = food.listingStockUnavailableLabel;
    final fssaiPending = food.showFssaiPendingOnListing;
    if (stockLabel != null && fssaiPending) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          TemporarilyUnavailableLabel(compact: compact, text: stockLabel),
          SizedBox(height: compact ? 2 : 4),
          TemporarilyUnavailableLabel(
            compact: compact,
            text: 'FSSAI pending',
          ),
        ],
      );
    }
    if (stockLabel != null) {
      if (stockLabel == 'Sold out') return soldOut;
      return TemporarilyUnavailableLabel(compact: compact, text: stockLabel);
    }
    if (!food.sellerAcceptingOrders) {
      return TemporarilyUnavailableLabel(
        compact: compact,
        text: food.blockedBySellerFssai ? 'FSSAI pending' : 'Not taking orders',
      );
    }
    if (cartQty == 0) {
      return addButton;
    }
    return qtyStepper;
  }
}
