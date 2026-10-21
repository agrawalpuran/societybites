import 'package:flutter/material.dart';

import '../models/data.dart';
import '../models/food_type.dart';
import '../services/api_service.dart';
import '../utils/listing_portion_label.dart';
import 'listing_image.dart';

/// Swiggy-style size picker before adding a multi-size listing to the cart.
class ListingVariantPickerSheet extends StatefulWidget {
  const ListingVariantPickerSheet({
    super.key,
    required this.seed,
    this.initialSelectedId,
    this.initialQty = 1,
  });

  final FoodItem seed;
  final String? initialSelectedId;
  final int initialQty;

  /// Loads siblings and returns the chosen variant + qty, or null if cancelled.
  static Future<({FoodItem food, int quantity})?> show(
    BuildContext context, {
    required FoodItem seed,
    String? initialSelectedId,
  }) {
    return showModalBottomSheet<({FoodItem food, int quantity})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ListingVariantPickerSheet(
        seed: seed,
        initialSelectedId: initialSelectedId,
      ),
    );
  }

  @override
  State<ListingVariantPickerSheet> createState() =>
      _ListingVariantPickerSheetState();
}

class _ListingVariantPickerSheetState extends State<ListingVariantPickerSheet> {
  List<FoodItem> _variants = const [];
  FoodItem? _selected;
  int _qty = 1;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _qty = widget.initialQty.clamp(1, 99);
    _selected = widget.seed;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ApiService.getListingVariants(widget.seed.id);
      if (!mounted) return;
      var variants = rows.map(FoodItem.fromJson).toList();
      if (variants.isEmpty) variants = [widget.seed];
      variants = [...variants]
        ..sort((a, b) {
          final byPrice = a.price.compareTo(b.price);
          if (byPrice != 0) return byPrice;
          return (a.variantLabel ?? '').compareTo(b.variantLabel ?? '');
        });
      final preferredId = widget.initialSelectedId ?? widget.seed.id;
      final match = variants.where((v) => v.id == preferredId);
      final selected = match.isNotEmpty
          ? match.first
          : variants.firstWhere(
              (v) => v.canAddToCart && !v.isKitchenClosed,
              orElse: () => variants.first,
            );
      final maxQty = selected.buyerMaxCartQuantity;
      setState(() {
        _variants = variants;
        _selected = selected;
        _loading = false;
        _qty = maxQty < 1 ? 1 : 1.clamp(1, maxQty);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _variants = [widget.seed];
        _selected = widget.seed;
        _loading = false;
        _error = 'Could not load sizes. You can still add this option.';
      });
    }
  }

  void _select(FoodItem food) {
    if (!food.canAddToCart || food.isKitchenClosed) return;
    setState(() {
      _selected = food;
      if (_qty > food.buyerMaxCartQuantity) {
        _qty = food.buyerMaxCartQuantity.clamp(1, 99);
      }
    });
  }

  void _confirm() {
    final selected = _selected;
    if (selected == null) return;
    if (!selected.canAddToCart || selected.isKitchenClosed) return;
    Navigator.pop(context, (food: selected, quantity: _qty));
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected ?? widget.seed;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Material(
          color: const Color(0xFFF8FAF9),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: maxHeight,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4DED9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                  child: Row(
                    children: [
                      ListingImage(
                        food: widget.seed,
                        width: 56,
                        height: 56,
                        borderRadius: 12,
                        iconSize: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.seed.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF101617),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                        color: const Color(0xFF3A4644),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFEAEFED)),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF0E5A47),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                          children: [
                            if (_error != null) ...[
                              Text(
                                _error!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF6A7774),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            const Text(
                              'Quantity',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF101617),
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Select any 1',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF6A7774),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 12),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFEAEFED),
                                ),
                              ),
                              child: Column(
                                children: [
                                  for (var i = 0; i < _variants.length; i++) ...[
                                    if (i > 0)
                                      const Divider(
                                        height: 1,
                                        color: Color(0xFFEAEFED),
                                      ),
                                    _VariantOptionRow(
                                      food: _variants[i],
                                      selected: _variants[i].id == selected.id,
                                      onTap: () => _select(_variants[i]),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, bottom > 0 ? 8 : 12),
                    child: Row(
                      children: [
                        _QtyStepper(
                          qty: _qty,
                          max: selected.buyerMaxCartQuantity,
                          onChanged: (next) => setState(() => _qty = next),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: selected.canAddToCart &&
                                      !selected.isKitchenClosed &&
                                      !_loading
                                  ? _confirm
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0E5A47),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    const Color(0xFFB8C4C0),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Text(
                                'Add Item | ₹${(selected.price * _qty).toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VariantOptionRow extends StatelessWidget {
  const _VariantOptionRow({
    required this.food,
    required this.selected,
    required this.onTap,
  });

  final FoodItem food;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = food.canAddToCart && !food.isKitchenClosed;
    final label = portionLabelForFood(food) ?? food.variantLabel ?? 'Size';
    final isVeg = food.foodType == foodTypeVeg;

    return InkWell(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              _VegMark(isVeg: isVeg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF101617),
                  ),
                ),
              ),
              Text(
                '₹${food.price.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF101617),
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: selected
                    ? const Color(0xFF0E5A47)
                    : const Color(0xFF8A9491),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VegMark extends StatelessWidget {
  const _VegMark({required this.isVeg});

  final bool isVeg;

  @override
  Widget build(BuildContext context) {
    final color = isVeg ? const Color(0xFF0E5A47) : const Color(0xFFC62828);
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.4),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Center(
        child: Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.qty,
    required this.max,
    required this.onChanged,
  });

  final int qty;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF0E5A47), width: 1.4),
        color: Colors.white,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: qty > 1 ? () => onChanged(qty - 1) : null,
            icon: const Icon(Icons.remove_rounded, size: 20),
            color: const Color(0xFF0E5A47),
          ),
          Text(
            '$qty',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: Color(0xFF0E5A47),
            ),
          ),
          IconButton(
            onPressed: qty < max ? () => onChanged(qty + 1) : null,
            icon: const Icon(Icons.add_rounded, size: 20),
            color: const Color(0xFF0E5A47),
          ),
        ],
      ),
    );
  }
}
