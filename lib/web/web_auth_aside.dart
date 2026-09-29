import 'package:flutter/material.dart';

import '../widgets/app_header.dart';
import 'web_breakpoints.dart';

/// Brand panel for wide-web sign-in. Android and iOS never use this.
class WebAuthAside extends StatelessWidget {
  const WebAuthAside({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: webGreenDark,
      child: Padding(
        padding: EdgeInsets.fromLTRB(48, 40, 40, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Brand(),
            Spacer(),
            Text(
              'Fresh flavors from\nyour Society and\nneighbourhood.',
              style: TextStyle(
                fontSize: 40,
                height: 1.05,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Homemade food from neighbours cooking nearby. Pickup from the cook.',
              style: TextStyle(
                fontSize: 16,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: Color(0xFFD5E8DF),
              ),
            ),
            SizedBox(height: 28),
            _Point(
              icon: Icons.groups_outlined,
              text: 'Neighbours cooking for neighbours',
            ),
            SizedBox(height: 12),
            _Point(
              icon: Icons.storefront_outlined,
              text: 'Pickup from the cook',
            ),
            SizedBox(height: 12),
            _Point(
              icon: Icons.verified_user_outlined,
              text: 'Sellers are responsible for their food',
            ),
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: webGreen,
            shape: BoxShape.circle,
          ),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              Icons.restaurant_menu_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
        SizedBox(width: 12),
        Text(
          kAppDisplayName,
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
      ],
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFB7D8C8), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
