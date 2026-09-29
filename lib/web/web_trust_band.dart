import 'package:flutter/material.dart';

import 'web_breakpoints.dart';

class WebTrustBand extends StatelessWidget {
  const WebTrustBand({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 860;
        final items = const [
          _TrustCard(
            icon: Icons.groups_outlined,
            title: 'Neighbours cooking for neighbours',
            body:
                'SocietyEats connects neighbours who cook with neighbours who want homemade food. We do not prepare the food.',
          ),
          _TrustCard(
            icon: Icons.storefront_outlined,
            title: 'Pickup from the cook',
            body:
                'Pickup, or any delivery a seller arranges, is between the buyer and the seller.',
          ),
          _TrustCard(
            icon: Icons.verified_user_outlined,
            title: 'Sellers are responsible',
            body:
                'Sellers are responsible for their food, hygiene, descriptions, pricing, and any licences that apply.',
          ),
        ];
        if (stacked) {
          return Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(height: 14),
                items[i],
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                Expanded(child: items[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TrustCard extends StatelessWidget {
  const _TrustCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD7E6DE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140E5A47),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 4, color: webGreen),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: webHeroWash,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFC9E3D4)),
                    ),
                    child: Icon(icon, size: 22, color: webGreen),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      color: webGreenDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    body,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF4E5E59),
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
