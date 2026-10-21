import 'package:flutter/material.dart';

import '../models/data.dart';
import '../utils/listing_catalog_order.dart';
import '../web/web_page_frame.dart';
import '../services/session_service.dart';
import '../widgets/listing_image.dart';
import 'seller_storefront_screen.dart';

class CatalogReorderScreen extends StatefulWidget {
  const CatalogReorderScreen({
    super.key,
    required this.initialItems,
    this.saveOrder,
  });

  final List<FoodItem> initialItems;
  final Future<List<String>> Function(List<String> orderedListingIds)? saveOrder;

  @override
  State<CatalogReorderScreen> createState() => _CatalogReorderScreenState();
}

class _CatalogReorderScreenState extends State<CatalogReorderScreen> {
  late List<FoodItem> _items;
  late List<String> _savedOrder;
  bool _saving = false;

  bool get _dirty =>
      _items.map((item) => item.id).join(',') != _savedOrder.join(',');

  @override
  void initState() {
    super.initState();
    _items = sortFoodItemsByCatalogOrder(widget.initialItems);
    _savedOrder = _items.map((item) => item.id).toList();
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final action = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'You have not saved your new catalog order yet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return action == true;
  }

  Future<void> _save() async {
    if (_saving || !_dirty) return;
    setState(() => _saving = true);
    try {
      final ids = _items.map((item) => item.id).toList();
      if (widget.saveOrder != null) {
        await widget.saveOrder!(ids);
      } else {
        throw Exception('Save handler is not configured');
      }
      final sellerId = await SessionService.getUserId();
      if (sellerId != null) {
        SellerStorefrontMemoryCache.clearFor(sellerId);
      }
      _savedOrder = List<String>.from(ids);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Catalog order saved')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save order: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _items.length) return;
    setState(() {
      final item = _items.removeAt(index);
      _items.insert(target, item);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmDiscard()) {
          if (context.mounted) Navigator.pop(context);
        }
      },
      child: centerOnWeb(
        context,
        Scaffold(
          backgroundColor: const Color(0xFFF8FAF9),
          appBar: AppBar(
            backgroundColor: const Color(0xFFF8FAF9),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () async {
                if (await _confirmDiscard()) {
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
            title: const Text(
              'Reorder Items',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF101617),
              ),
            ),
            actions: [
              TextButton(
                onPressed: _saving || !_dirty ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Save Order',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ],
          ),
          body: _items.isEmpty
              ? const Center(
                  child: Text(
                    'No regular catalog items to reorder.',
                    style: TextStyle(color: Color(0xFF6A7774)),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Text(
                        'Drag items or use arrows. Buyers will see this order on your storefront.',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF6A7774),
                          height: 1.35,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        itemCount: _items.length,
                        onReorder: (oldIndex, newIndex) {
                          setState(() {
                            if (newIndex > oldIndex) newIndex -= 1;
                            final item = _items.removeAt(oldIndex);
                            _items.insert(newIndex, item);
                          });
                        },
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return _ReorderRow(
                            key: ValueKey(item.id),
                            index: index,
                            total: _items.length,
                            item: item,
                            onMoveUp: () => _move(index, -1),
                            onMoveDown: () => _move(index, 1),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
        maxWidth: 720,
      ),
    );
  }
}

class _ReorderRow extends StatelessWidget {
  const _ReorderRow({
    super.key,
    required this.index,
    required this.total,
    required this.item,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final int index;
  final int total;
  final FoodItem item;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  String get _statusLabel {
    if (item.isDraft) return 'Draft';
    if (item.isExpired) return 'Expired';
    if (item.status == 'paused') return 'Paused';
    if (item.status == 'sold_out') return 'Sold out';
    if (item.isMadeToOrder) return 'Made to order';
    return 'Active';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8E6)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_handle_rounded, color: Color(0xFF9AA8A4)),
            ),
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ListingImage(
                food: item,
                width: 52,
                height: 52,
                borderRadius: 10,
              ),
            ),
          ],
        ),
        title: Text(
          item.name,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF101617),
          ),
        ),
        subtitle: Text(
          '#${index + 1} · $_statusLabel',
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF6A7774),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: index == 0 ? null : onMoveUp,
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: index >= total - 1 ? null : onMoveDown,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
