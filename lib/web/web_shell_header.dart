import 'package:flutter/material.dart';

import '../models/food_type.dart';
import '../services/session_service.dart';
import '../widgets/app_header.dart';
import '../widgets/cart_header_button.dart';
import 'web_breakpoints.dart';

class WebShellHeader extends StatefulWidget {
  const WebShellHeader({
    super.key,
    required this.selectedTab,
    required this.onSelectTab,
    required this.selectedFoodType,
    required this.onFoodTypeChanged,
    required this.onSearchChanged,
    this.onSignIn,
    this.signedIn,
    this.kitchenAttentionCount = 0,
  });

  final int selectedTab;
  final ValueChanged<int> onSelectTab;
  final String? selectedFoodType;
  final ValueChanged<String?> onFoodTypeChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback? onSignIn;
  final bool? signedIn;
  final int kitchenAttentionCount;

  @override
  State<WebShellHeader> createState() => _WebShellHeaderState();
}

class _WebShellHeaderState extends State<WebShellHeader> {
  final _searchController = TextEditingController();
  String? _userName;

  @override
  void initState() {
    super.initState();
    _loadIdentity();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadIdentity() async {
    final name = await SessionService.getUserName();
    if (!mounted) return;
    setState(() => _userName = name);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Container(
        key: const Key('web-shell-header'),
        height: 64,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: webLine)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final pageWidth = constraints.maxWidth;
            final pad = webPagePadding(pageWidth);
            final framed = pageWidth > webFrameMaxWidth
                ? webFrameMaxWidth
                : pageWidth;
            final rowBudget = framed - pad * 2;
            final compactNav = rowBudget < 1040;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: webFrameMaxWidth),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: pad),
                  child: Row(
                    children: [
                      _Wordmark(onTap: () => widget.onSelectTab(0)),
                      const SizedBox(width: 8),
                      _HomeButton(
                        selected: widget.selectedTab == 0,
                        compact: compactNav,
                        onTap: () => widget.onSelectTab(0),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: _SearchField(
                          controller: _searchController,
                          onChanged: widget.onSearchChanged,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _VegToggle(
                        selected: widget.selectedFoodType == foodTypeVeg,
                        onChanged: (vegOnly) {
                          widget.onFoodTypeChanged(
                            vegOnly ? foodTypeVeg : null,
                          );
                        },
                      ),
                      const SizedBox(width: 4),
                      _NavLink(
                        label: 'Explore',
                        icon: Icons.explore_outlined,
                        selected: widget.selectedTab == 0,
                        compact: compactNav,
                        onTap: () => widget.onSelectTab(0),
                      ),
                      _NavLink(
                        label: 'My Kitchen',
                        icon: Icons.grid_view_rounded,
                        selected: widget.selectedTab == 2,
                        compact: compactNav,
                        badgeCount: widget.kitchenAttentionCount,
                        onTap: () => widget.onSelectTab(2),
                      ),
                      _NavLink(
                        label: 'Orders',
                        icon: Icons.shopping_bag_outlined,
                        selected: widget.selectedTab == 1,
                        compact: compactNav,
                        onTap: () => widget.onSelectTab(1),
                      ),
                      const SizedBox(width: 4),
                      const CartHeaderButton(),
                      const SizedBox(width: 4),
                      if (widget.signedIn == false)
                        TextButton(
                          onPressed: widget.onSignIn,
                          child: const Text(
                            'Sign in',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: webGreen,
                            ),
                          ),
                        )
                      else
                        _ProfileButton(
                          name: _userName,
                          selected: widget.selectedTab == 3,
                          onTap: () => widget.onSelectTab(3),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              kAppDisplayName,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: webGreenDark,
                letterSpacing: -0.3,
              ),
            ),
            SizedBox(width: 4),
            Icon(Icons.restaurant_menu_rounded, color: webGreen, size: 18),
          ],
        ),
      ),
    );
  }
}

class _HomeButton extends StatelessWidget {
  const _HomeButton({
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Home',
      child: Material(
        color: selected ? const Color(0xFFE5F2EA) : const Color(0xFFF4F7F5),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: const Key('web-home-button'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: 7,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.home_rounded,
                  size: 18,
                  color: selected ? webGreen : webMuted,
                ),
                if (!compact) ...[
                  const SizedBox(width: 5),
                  Text(
                    'Home',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: selected ? webGreen : webMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: SizedBox(
        height: 38,
        child: TextField(
          key: const Key('web-home-search'),
          controller: controller,
          onChanged: onChanged,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: webInk,
          ),
          decoration: InputDecoration(
            hintText: 'Search dishes, kitchens...',
            hintStyle: const TextStyle(
              color: Color(0xFF9AA5A1),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              size: 18,
              color: Color(0xFF8A9491),
            ),
            filled: true,
            fillColor: const Color(0xFFF7F8F7),
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: webLine),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: webLine),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: webGreen),
            ),
            isDense: true,
          ),
        ),
      ),
    );
  }
}

class _VegToggle extends StatelessWidget {
  const _VegToggle({
    required this.selected,
    required this.onChanged,
  });

  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? webGreen : const Color(0xFFF4F7F5),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        key: const Key('web-veg-toggle'),
        onTap: () => onChanged(!selected),
        borderRadius: BorderRadius.circular(11),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: selected ? webGreen : webLine),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: selected ? Colors.white : const Color(0xFF14804A),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                'Veg',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : webGreen,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavLink extends StatelessWidget {
  const _NavLink({
    required this.label,
    required this.icon,
    required this.selected,
    required this.compact,
    required this.onTap,
    this.badgeCount = 0,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final color = selected ? webGreen : webMuted;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 18, color: color),
                  if (badgeCount > 0)
                    Positioned(
                      right: -6,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFB42318),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          badgeCount > 9 ? '9+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (!compact) ...[
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileButton extends StatelessWidget {
  const _ProfileButton({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String? name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final trimmed = name?.trim() ?? '';
    final initial = trimmed.isEmpty ? null : trimmed[0].toUpperCase();
    return Tooltip(
      message: 'Profile',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? webGreen : const Color(0xFFE7F2EA),
            shape: BoxShape.circle,
          ),
          child: initial == null
              ? Icon(
                  Icons.person_rounded,
                  size: 18,
                  color: selected ? Colors.white : webGreen,
                )
              : Text(
                  initial,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: selected ? Colors.white : webGreenDark,
                  ),
                ),
        ),
      ),
    );
  }
}
