import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/cart_controller.dart';
import '../services/session_service.dart';
import 'cart_header_button.dart';

/// On-screen product name. Internal identifiers may still say SocietyBites.
const kAppDisplayName = 'SocietyEats';

class AppHeader extends StatefulWidget {
  const AppHeader({
    super.key,
    this.leading,
    this.actions,
    this.showCart = true,
    this.showUser = true,
    this.cartItemCount,
    this.onCartPressed,
    this.padding = const EdgeInsets.fromLTRB(20, 14, 20, 0),
  });

  final Widget? leading;
  final Widget? actions;
  final bool showCart;
  final bool showUser;
  final int? cartItemCount;
  final VoidCallback? onCartPressed;
  final EdgeInsets padding;

  @override
  State<AppHeader> createState() => _AppHeaderState();
}

class _AppHeaderState extends State<AppHeader> {
  String? _name;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    var name = await SessionService.getUserName();

    final userId = await SessionService.getUserId();
    if (userId != null && name == null) {
      try {
        final profile = await ApiService.getMe();
        await SessionService.cacheProfileFromApi(profile);
        name = await SessionService.getUserName();
      } catch (_) {}
    }

    if (!mounted) return;

    setState(() {
      _name = name;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: widget.padding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
          if (widget.leading != null) widget.leading!,
          if (widget.leading == null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      kAppDisplayName,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: Color(0xFF0A4638),
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.restaurant_menu_rounded,
                      color: Color(0xFF0E5A47),
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (widget.actions != null) ...[
                  widget.actions!,
                  const SizedBox(width: 10),
                ],
                if (widget.showCart)
                  ListenableBuilder(
                    listenable: CartController.instance,
                    builder: (context, _) {
                      final count = widget.cartItemCount ??
                          CartController.instance.itemCount;
                      if (count <= 0) return const SizedBox.shrink();
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CartHeaderButton(
                            itemCountOverride: widget.cartItemCount,
                            onPressed: widget.onCartPressed,
                          ),
                          if (widget.showUser) const SizedBox(width: 10),
                        ],
                      );
                    },
                  ),
                if (widget.showUser)
                  Flexible(
                    fit: FlexFit.tight,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _UserInfoColumn(name: _name),
                    ),
                  ),
              ],
            ),
          ),
          ],
        ),
      ),
    );
  }
}

class _UserInfoColumn extends StatelessWidget {
  const _UserInfoColumn({required this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    if (name == null || name!.isEmpty) {
      return const Icon(
        Icons.person_rounded,
        color: Color(0xFF0E5A47),
        size: 22,
      );
    }

    return Text(
      name!,
      textAlign: TextAlign.right,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 13,
        height: 1.2,
        color: Color(0xFF4A5A57),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
