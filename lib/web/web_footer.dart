import 'package:flutter/material.dart';

import '../widgets/app_header.dart';
import 'web_breakpoints.dart';

class WebFooter extends StatelessWidget {
  const WebFooter({
    super.key,
    required this.onPrivacy,
    required this.onTerms,
    required this.onHelp,
    required this.onExplore,
    required this.onOrders,
    required this.onKitchen,
    required this.onProfile,
  });

  final VoidCallback onPrivacy;
  final VoidCallback onTerms;
  final VoidCallback onHelp;
  final VoidCallback onExplore;
  final VoidCallback onOrders;
  final VoidCallback onKitchen;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(4, 28, 4, 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: webLine)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 860;
          final columns = [
            const _BrandColumn(),
            _LinkColumn(
              title: 'Marketplace',
              links: [
                _FooterLink('Explore', onExplore),
                _FooterLink('Orders', onOrders),
                _FooterLink('My Kitchen', onKitchen),
                _FooterLink('Profile', onProfile),
              ],
            ),
            _LinkColumn(
              title: 'Support',
              links: [
                _FooterLink('Help Center', onHelp),
                _FooterLink('Privacy Policy', onPrivacy),
                _FooterLink('Terms of Service', onTerms),
              ],
            ),
          ];
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final column in columns) ...[
                  column,
                  const SizedBox(height: 22),
                ],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < columns.length; i++)
                Expanded(child: columns[i]),
            ],
          );
        },
      ),
    );
  }
}

class _BrandColumn extends StatelessWidget {
  const _BrandColumn();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kAppDisplayName,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: webGreenDark,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'A homemade-food marketplace for neighbours in the same society.',
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            fontWeight: FontWeight.w500,
            color: webMuted,
          ),
        ),
      ],
    );
  }
}

class _LinkColumn extends StatelessWidget {
  const _LinkColumn({required this.title, required this.links});

  final String title;
  final List<_FooterLink> links;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: webInk,
          ),
        ),
        const SizedBox(height: 10),
        for (final link in links)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: link.onTap,
              child: Text(
                link.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: webMuted,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FooterLink {
  const _FooterLink(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;
}
