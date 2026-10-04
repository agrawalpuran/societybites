import 'package:flutter/material.dart';

import '../models/selling_reach.dart';
import '../screens/home_listing_filter.dart';

/// Compact Home distance pill. Opens a small menu; does not fetch.
class HomeDistanceChip extends StatelessWidget {
  const HomeDistanceChip({
    super.key,
    required this.reach,
    required this.selected,
    required this.itemCount,
    required this.onSelected,
    this.listingType = HomeListingType.all,
    this.onListingTypeSelected,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 0),
  });

  final SellingReach reach;
  final BuyerDistanceChoice? selected;
  final int itemCount;
  final ValueChanged<BuyerDistanceChoice> onSelected;
  final HomeListingType listingType;
  final ValueChanged<HomeListingType>? onListingTypeSelected;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final choice = effectiveBuyerDistance(selected, reach);
    final label = homeDistanceMenuLabel(choice, reach);
    final countLabel = homeDishCountLabel(itemCount, choice, reach);

    return Padding(
      padding: padding,
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
              onTap: () => _openMenu(context, choice),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.place_outlined,
                      size: 14,
                      color: Color(0xFF0E5A47),
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
          if (onListingTypeSelected != null) ...[
            const SizedBox(width: 8),
            _HomeTypeChip(
              listingType: listingType,
              onSelected: onListingTypeSelected!,
            ),
          ],
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

  Future<void> _openMenu(
    BuildContext context,
    BuyerDistanceChoice current,
  ) async {
    final picked = await showHomeDistanceMenu(
      context,
      reach: reach,
      current: current,
    );
    if (picked != null) onSelected(picked);
  }
}

Future<BuyerDistanceChoice?> showHomeDistanceMenu(
  BuildContext context, {
  required SellingReach reach,
  required BuyerDistanceChoice current,
}) {
  final choices = homeDistanceMenuChoices(reach);
  return _showAnchoredMenu<BuyerDistanceChoice>(
    context,
    options: [
      for (final choice in choices)
        _AnchoredMenuOption(
          value: choice,
          label: homeDistanceMenuLabel(choice, reach),
          selected: choice == current,
          key: Key('home-distance-option-${choice.optionKey}'),
        ),
    ],
  );
}

Future<BuyerDistanceChoice?> showHomeDistanceSheet(
  BuildContext context, {
  required SellingReach reach,
  required BuyerDistanceChoice current,
}) {
  return showHomeDistanceMenu(
    context,
    reach: reach,
    current: current,
  );
}

Future<HomeListingType?> showHomeListingTypeMenu(
  BuildContext context, {
  required HomeListingType current,
}) {
  return _showAnchoredMenu<HomeListingType>(
    context,
    options: [
      for (final type in HomeListingType.values)
        _AnchoredMenuOption(
          value: type,
          label: homeListingTypeLabel(type),
          selected: type == current,
          key: Key('home-listing-type-${type.name}'),
        ),
    ],
  );
}

class _AnchoredMenuOption<T> {
  const _AnchoredMenuOption({
    required this.value,
    required this.label,
    required this.selected,
    required this.key,
  });

  final T value;
  final String label;
  final bool selected;
  final Key key;
}

Future<T?> _showAnchoredMenu<T>(
  BuildContext context, {
  required List<_AnchoredMenuOption<T>> options,
}) {
  final box = context.findRenderObject() as RenderBox;
  final overlay = Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
  final below = Rect.fromLTWH(
    origin.dx,
    origin.dy + box.size.height + 4,
    box.size.width,
    1,
  );
  final position = RelativeRect.fromRect(below, Offset.zero & overlay.size);
  return showMenu<T>(
    context: context,
    position: position,
    elevation: 8,
    color: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    constraints: const BoxConstraints(minWidth: 176, maxWidth: 230),
    items: [
      for (final option in options)
        PopupMenuItem<T>(
          key: option.key,
          value: option.value,
          height: 42,
          child: Row(
            children: [
              Icon(
                Icons.check_rounded,
                size: 18,
                color: option.selected
                    ? const Color(0xFF0E5A47)
                    : Colors.transparent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  option.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: option.selected ? FontWeight.w700 : FontWeight.w500,
                    color: const Color(0xFF101617),
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class _HomeTypeChip extends StatelessWidget {
  const _HomeTypeChip({
    required this.listingType,
    required this.onSelected,
  });

  final HomeListingType listingType;
  final ValueChanged<HomeListingType> onSelected;

  bool get _active => listingType != HomeListingType.all;

  @override
  Widget build(BuildContext context) {
    final background = _active
        ? const Color(0xFF0E5A47)
        : const Color(0xFFF3F7F5);
    final foreground = _active ? Colors.white : const Color(0xFF0E5A47);
    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: _active ? const Color(0xFF0E5A47) : const Color(0xFFD4E8DF),
        ),
      ),
      child: InkWell(
        key: const Key('home-listing-type-chip'),
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openMenu(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                homeListingTypeLabel(listingType),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: foreground,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMenu(BuildContext context) async {
    final picked = await showHomeListingTypeMenu(
      context,
      current: listingType,
    );
    if (picked != null) onSelected(picked);
  }
}
