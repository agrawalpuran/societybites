import 'package:flutter/material.dart';

import '../models/data.dart';
import '../widgets/preorder_widgets.dart';

/// Full description and photo for one pre-order dish. Adding still updates
/// the campaign quantities; it does not start a regular order.
class BuyerPreOrderProductScreen extends StatefulWidget {
  const BuyerPreOrderProductScreen({
    super.key,
    required this.product,
    required this.readyLabel,
    required this.availabilityLabel,
    required this.acceptingOrders,
    required this.initialQuantity,
    required this.onChangeQuantity,
    this.description,
    this.portion,
  });

  final PreOrderProduct product;
  final String? description;
  final String? portion;
  final String readyLabel;
  final String availabilityLabel;
  final bool acceptingOrders;
  final int initialQuantity;
  final bool Function(int delta) onChangeQuantity;

  @override
  State<BuyerPreOrderProductScreen> createState() =>
      _BuyerPreOrderProductScreenState();
}

class _BuyerPreOrderProductScreenState
    extends State<BuyerPreOrderProductScreen> {
  late int _quantity;

  @override
  void initState() {
    super.initState();
    _quantity = widget.initialQuantity;
  }

  bool get _soldOut =>
      widget.product.inventoryMode == 'limited' && widget.product.quantity <= 0;

  void _bump(int delta) {
    final applied = widget.onChangeQuantity(delta);
    if (!applied || !mounted) return;
    setState(() => _quantity = (_quantity + delta).clamp(0, 999));
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final description = widget.description?.trim();
    return Scaffold(
      key: const Key('preorder-product-detail'),
      backgroundColor: preorderBackground,
      appBar: AppBar(
        backgroundColor: preorderBackground,
        foregroundColor: preorderText,
        elevation: 0,
        title: const Text(
          'Details',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PreOrderCoverImage(
                          imageUrl: product.imageUrl,
                          width: double.infinity,
                          height: 280,
                          borderRadius: 20,
                        ),
                        const SizedBox(height: 16),
                        const PreOrderBadge(compact: true),
                        const SizedBox(height: 8),
                        Text(
                          product.name,
                          style: const TextStyle(
                            color: preorderText,
                            fontSize: 26,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          formatMoney(product.price),
                          style: const TextStyle(
                            color: preorderGreen,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (description != null && description.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Text(
                            description,
                            key: const Key('preorder-product-description'),
                            style: const TextStyle(
                              color: preorderText,
                              fontSize: 15,
                              height: 1.45,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        if (widget.portion != null &&
                            widget.portion!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            widget.portion!,
                            style: const TextStyle(
                              color: preorderMuted,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          widget.readyLabel,
                          style: const TextStyle(
                            color: preorderGreen,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.availabilityLabel,
                          style: TextStyle(
                            color: _soldOut
                                ? const Color(0xFFD94F4F)
                                : preorderMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [_quantityControl()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quantityControl() {
    if (_quantity == 0) {
      final enabled = widget.acceptingOrders && !_soldOut;
      return FilledButton(
        onPressed: enabled ? () => _bump(1) : null,
        style: FilledButton.styleFrom(
          backgroundColor: preorderGreen,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFE8EDEB),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          _soldOut ? 'Sold out' : 'Add to Pre-order',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _roundButton(Icons.remove, () => _bump(-1)),
        SizedBox(
          width: 34,
          child: Text(
            '$_quantity',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              color: preorderText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        _roundButton(
          Icons.add,
          widget.acceptingOrders && !_soldOut ? () => _bump(1) : null,
          filled: true,
        ),
      ],
    );
  }

  Widget _roundButton(
    IconData icon,
    VoidCallback? onTap, {
    bool filled = false,
  }) {
    return IconButton(
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: filled ? preorderGreen : Colors.white,
        foregroundColor: filled ? Colors.white : preorderText,
        disabledBackgroundColor: const Color(0xFFE8EDEB),
        side: filled ? null : const BorderSide(color: Color(0xFFD4DBD8)),
      ),
      icon: Icon(icon, size: 18),
    );
  }
}
