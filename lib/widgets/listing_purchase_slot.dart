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
    if (food.isExpired) {
      return TemporarilyUnavailableLabel(compact: compact);
    }
    if (food.quantity <= 0) {
      return soldOut;
    }
    if (cartQty == 0) {
      return addButton;
    }
    return qtyStepper;
  }
}
