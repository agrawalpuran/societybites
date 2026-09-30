import 'package:flutter/material.dart';

import '../models/selling_reach.dart';
import '../screens/home_listing_filter.dart';

/// Compact Home distance pill. Opens a sheet; does not fetch.
class HomeDistanceChip extends StatelessWidget {
  const HomeDistanceChip({
    super.key,
    required this.reach,
    required this.selected,
    required this.itemCount,
    required this.onSelected,
  });

  final SellingReach reach;
  final BuyerDistanceChoice? selected;
  final int itemCount;
  final ValueChanged<BuyerDistanceChoice> onSelected;

  @override
  Widget build(BuildContext context) {
    final choice = effectiveBuyerDistance(selected, reach);
    final label = buyerDistanceLabel(choice, reach);
    final countLabel = itemCount == 1
        ? (choice.societyOnly ? '1 item' : '1 item nearby')
        : (choice.societyOnly
              ? '$itemCount items'
              : '$itemCount items nearby');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        children: [
          Material(
            color: const Color(0xFFF3F7F5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFFD4E8DF)),
            ),
            child: InkWell(
              key: const Key('home-distance-chip'),
              borderRadius: BorderRadius.circular(20),
              onTap: () => _openSheet(context, choice),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      choice.isExtended
                          ? Icons.apartment_outlined
                          : Icons.place_outlined,
                      size: 14,
                      color: const Color(0xFF0E5A47),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0E5A47),
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: Color(0xFF0E5A47),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              countLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6A7774),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSheet(
    BuildContext context,
    BuyerDistanceChoice current,
  ) async {
    final picked = await showHomeDistanceSheet(
      context,
      reach: reach,
      current: current,
    );
    if (picked != null) onSelected(picked);
  }
}

Future<BuyerDistanceChoice?> showHomeDistanceSheet(
  BuildContext context, {
  required SellingReach reach,
  required BuyerDistanceChoice current,
}) {
  return showModalBottomSheet<BuyerDistanceChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _DistanceSheet(reach: reach, current: current),
  );
}

class _DistanceSheet extends StatefulWidget {
  const _DistanceSheet({required this.reach, required this.current});

  final SellingReach reach;
  final BuyerDistanceChoice current;

  @override
  State<_DistanceSheet> createState() => _DistanceSheetState();
}

class _DistanceSheetState extends State<_DistanceSheet> {
  late BuyerDistanceChoice _pending = widget.current;

  @override
  Widget build(BuildContext context) {
    final choices = buyerDistanceChoices(widget.reach);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E5E3),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'How far do you want to explore?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF101617),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Show me food from my society and nearby communities',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF6A7774),
              ),
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.5,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [for (final choice in choices) _option(choice)],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                key: const Key('home-distance-apply'),
                onPressed: () => Navigator.pop(context, _pending),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0E5A47),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Apply',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _option(BuyerDistanceChoice choice) {
    final selected = _pending == choice;
    final subtitle = buyerDistanceSubtitle(choice, widget.reach);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? const Color(0xFFF3F7F5) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected
                ? const Color(0xFF0E5A47)
                : const Color(0xFFE6EBE9),
          ),
        ),
        child: InkWell(
          key: Key('home-distance-option-${choice.optionKey}'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _pending = choice),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        buyerDistanceLabel(choice, widget.reach),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF101617),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF6A7774),
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_rounded,
                    color: Color(0xFF0E5A47),
                    size: 18,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
