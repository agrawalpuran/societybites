import 'dart:async';

import 'package:flutter/material.dart';

import '../models/data.dart';
import '../models/food_type.dart';
import '../services/api_service.dart';
import '../services/listing_variants_cache.dart';
import '../utils/listing_portion_label.dart';
import '../web/web_breakpoints.dart';
import 'content_skeleton.dart';
import 'listing_image.dart';

/// Swiggy-style size picker before adding a multi-size listing to the cart.
class ListingVariantPickerSheet extends StatefulWidget {
  const ListingVariantPickerSheet({
    super.key,
    required this.seed,
    this.initialSelectedId,
    this.initialQty = 1,
    this.asWebDialog = false,
  });

  final FoodItem seed;
  final String? initialSelectedId;
  final int initialQty;
  final bool asWebDialog;

  /// Loads siblings and returns the chosen variant + qty, or null if cancelled.
  static Future<({FoodItem food, int quantity})?> show(
    BuildContext context, {
    required FoodItem seed,
    String? initialSelectedId,
  }) {
    final picker = ListingVariantPickerSheet(
      seed: seed,
      initialSelectedId: initialSelectedId,
      asWebDialog: useWebMarketplaceLayout(context),
    );
    if (useWebMarketplaceLayout(context)) {
      return showDialog<({FoodItem food, int quantity})>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.45),
        builder: (ctx) => Dialog(
          backgroundColor: const Color(0xFFF8FAF9),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440, maxHeight: 520),
            child: picker,
          ),
        ),
      );
    }
    return showModalBottomSheet<({FoodItem food, int quantity})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => picker,
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
  bool _fetchingSiblings = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _qty = widget.initialQty.clamp(1, 99);
    final cached = ListingVariantsCache.getForSeed(widget.seed);
    if (cached != null) {
      _applyRows(cached);
    } else {
      _variants = [widget.seed];
      _selected = widget.seed;
      unawaited(_load());
    }
  }

  List<FoodItem> _sortedVariants(List<FoodItem> variants) {
    return [...variants]
      ..sort((a, b) {
        final byPrice = a.price.compareTo(b.price);
        if (byPrice != 0) return byPrice;
        return (a.variantLabel ?? '').compareTo(b.variantLabel ?? '');
      });
  }

  void _applyRows(List<Map<String, dynamic>> rows) {
    var variants = rows.map(FoodItem.fromJson).toList();
    if (variants.isEmpty) variants = [widget.seed];
    variants = _sortedVariants(variants);
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
      _fetchingSiblings = false;
      _error = null;
      _qty = maxQty < 1 ? 1 : 1.clamp(1, maxQty);
    });
  }

  Future<void> _load() async {
    if (_fetchingSiblings) return;
    setState(() {
      _fetchingSiblings = true;
      _error = null;
    });
    try {
      final rows = await ApiService.getListingVariants(widget.seed.id);
      if (!mounted) return;
      ListingVariantsCache.put(widget.seed, rows);
      _applyRows(rows);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_variants.isEmpty) {
          _variants = [widget.seed];
          _selected = widget.seed;
        }
        _fetchingSiblings = false;
        _error = 'Could not load all sizes. You can still add this option.';
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

  int get _expectedOptionCount {
    final count = widget.seed.variantOptionCount ?? 0;
    if (count > 1) return count;
    return _variants.length;
  }

  Widget _buildOptionsList(FoodItem selected) {
    final expectedMore = _fetchingSiblings &&
        _expectedOptionCount > _variants.length;
    final skeletonRows = expectedMore
        ? (_expectedOptionCount - _variants.length).clamp(1, 3)
        : 0;

    return ListView(
      shrinkWrap: true,
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
        if (_fetchingSiblings)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: LinearProgressIndicator(
              minHeight: 2,
              color: Color(0xFF0E5A47),
              backgroundColor: Color(0xFFE8F0EC),
            ),
          ),
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
            border: Border.all(color: const Color(0xFFEAEFED)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < _variants.length; i++) ...[
                if (i > 0)
                  const Divider(height: 1, color: Color(0xFFEAEFED)),
                _VariantOptionRow(
                  food: _variants[i],
                  selected: _variants[i].id == selected.id,
                  onTap: () => _select(_variants[i]),
                ),
              ],
              for (var s = 0; s < skeletonRows; s++) ...[
                if (_variants.isNotEmpty || s > 0)
                  const Divider(height: 1, color: Color(0xFFEAEFED)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: SkeletonBlock(height: 20, radius: 8),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChrome(BuildContext context, FoodItem selected) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!widget.asWebDialog) ...[
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD4DED9),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
        Padding(
          padding: EdgeInsets.fromLTRB(16, widget.asWebDialog ? 16 : 14, 8, 8),
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
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: widget.asWebDialog
                ? 300
                : MediaQuery.sizeOf(context).height * 0.42,
          ),
          child: _buildOptionsList(selected),
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
                              !selected.isKitchenClosed
                          ? _confirm
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0E5A47),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFB8C4C0),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected ?? widget.seed;

    if (widget.asWebDialog) {
      return _buildChrome(context, selected);
    }

    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Material(
          color: const Color(0xFFF8FAF9),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: _buildChrome(context, selected),
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
