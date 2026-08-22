import 'package:flutter/material.dart';

import '../models/data.dart';
import '../services/api_service.dart';

const preorderGreen = Color(0xFF0E5A47);
const preorderBackground = Color(0xFFF8FAF9);
const preorderText = Color(0xFF101617);
const preorderMuted = Color(0xFF6A7774);
const preorderBorder = Color(0xFFEAEFED);

class PreOrderCoverImage extends StatelessWidget {
  const PreOrderCoverImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height = 160,
    this.borderRadius = 18,
  });

  final String? imageUrl;
  final double? width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final normalized = imageUrl?.trim();
    final resolvedUrl = normalized == null || normalized.isEmpty
        ? null
        : ApiService.imageUrl(normalized);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: resolvedUrl == null
            ? const PreOrderCoverPlaceholder()
            : Image.network(
                resolvedUrl,
                key: const ValueKey('preorder-cover-image'),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const PreOrderCoverPlaceholder(),
              ),
      ),
    );
  }
}

class PreOrderCoverPlaceholder extends StatelessWidget {
  const PreOrderCoverPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('preorder-cover-placeholder'),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE8F5EE), Color(0xFFFFF0E6)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.event_note_rounded, color: preorderGreen, size: 42),
      ),
    );
  }
}

String cleanApiError(Object error) {
  var message = error.toString();
  if (message.startsWith('Exception: ')) {
    message = message.substring('Exception: '.length);
  }
  final lower = message.toLowerCase();
  if (lower.contains('socket') ||
      lower.contains('connection') ||
      lower.contains('failed host lookup') ||
      lower.contains('xmlhttprequest')) {
    return 'Could not reach SocietyBites. Check your connection and try again.';
  }
  if (lower.contains('cutoff')) {
    return 'The order cutoff has passed. Refresh to see the latest campaign status.';
  }
  if (lower.contains('already closed') || lower.contains('status "closed"')) {
    return 'This campaign is already closed.';
  }
  return message.isEmpty ? 'Something went wrong. Please try again.' : message;
}

String formatMoney(double value) {
  final rounded = value.round();
  final digits = rounded.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '₹$buffer';
}

String formatDateTime(DateTime value) {
  final local = value.toLocal();
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${weekdays[local.weekday - 1]}, ${local.day} '
      '${months[local.month - 1]} · ${formatTime(local)}';
}

String formatTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour == 0
      ? 12
      : local.hour > 12
      ? local.hour - 12
      : local.hour;
  return '$hour:${local.minute.toString().padLeft(2, '0')} '
      '${local.hour >= 12 ? 'PM' : 'AM'}';
}

String formatShortCutoff(DateTime value) {
  final local = value.toLocal();
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return 'By ${weekdays[local.weekday - 1]} ${formatTime(local)}';
}

String campaignDisplayStatus(PreOrderCampaign campaign) {
  if (campaign.status == 'open' &&
      !DateTime.now().isBefore(campaign.orderCutoffAt)) {
    return 'closed';
  }
  return campaign.status;
}

String productionHeading({
  required String status,
  required DateTime orderCutoffAt,
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  return status == 'open' && reference.isBefore(orderCutoffAt)
      ? 'CURRENT DEMAND'
      : 'FINAL QUANTITY TO PREPARE';
}

class PreOrderStatusBadge extends StatelessWidget {
  const PreOrderStatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final (background, foreground) = switch (normalized) {
      'open' => (const Color(0xFFE8F5EE), preorderGreen),
      'draft' => (const Color(0xFFFFF8E8), const Color(0xFF9A6B00)),
      'cancelled' => (const Color(0xFFFFF0F0), const Color(0xFFD94F4F)),
      _ => (const Color(0xFFF0F2F1), const Color(0xFF596461)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        normalized[0].toUpperCase() + normalized.substring(1),
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class PreOrderCampaignCard extends StatelessWidget {
  const PreOrderCampaignCard({
    super.key,
    required this.campaign,
    required this.onTap,
    this.compact = false,
  });

  final PreOrderCampaign campaign;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: preorderBorder),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: EdgeInsets.all(compact ? 16 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PreOrderCoverImage(
                imageUrl: campaign.coverImageUrl,
                width: double.infinity,
                height: compact ? 96 : 140,
                borderRadius: 14,
              ),
              SizedBox(height: compact ? 12 : 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      campaign.title,
                      style: TextStyle(
                        fontSize: compact ? 16 : 18,
                        fontWeight: FontWeight.w800,
                        color: preorderText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  PreOrderStatusBadge(status: campaignDisplayStatus(campaign)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${campaign.totalOrders} orders · '
                '${formatMoney(campaign.foodSubtotal)} food value',
                style: const TextStyle(
                  fontSize: 14,
                  color: preorderGreen,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.lock_clock_outlined,
                    size: 17,
                    color: preorderMuted,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Closes ${formatDateTime(campaign.orderCutoffAt)}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: preorderMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.restaurant_rounded,
                    size: 17,
                    color: preorderMuted,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Fulfilment ${formatDateTime(campaign.fulfilmentAt)}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: preorderMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFFADB5B2),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PreOrderEmptyState extends StatelessWidget {
  const PreOrderEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.action,
  });

  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7F4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD4E8DF)),
      ),
      child: Column(
        children: [
          const Icon(Icons.event_note_rounded, color: preorderGreen, size: 34),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: preorderText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              height: 1.4,
              color: preorderMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

class HomePreOrderCampaignCard extends StatelessWidget {
  const HomePreOrderCampaignCard({
    super.key,
    required this.campaign,
    required this.onTap,
  });

  static const double cardWidth = 160;
  static const double cardHeight = 178;
  static const double coverHeight = 88;

  final PreOrderCampaign campaign;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: preorderBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PreOrderCoverImage(
                  imageUrl: campaign.coverImageUrl,
                  width: cardWidth,
                  height: coverHeight,
                  borderRadius: 0,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          campaign.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: preorderText,
                            fontSize: 13,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          campaign.sellerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: preorderMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          formatShortCutoff(campaign.orderCutoffAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: preorderGreen,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
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

class BuyerPreOrderCampaignCard extends StatelessWidget {
  const BuyerPreOrderCampaignCard({
    super.key,
    required this.campaign,
    required this.onTap,
    this.onSellerTap,
    this.compact = false,
  });

  final PreOrderCampaign campaign;
  final VoidCallback onTap;
  final VoidCallback? onSellerTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final previews = campaign.products.take(compact ? 2 : 3).toList();
    return Container(
      width: compact ? 300 : double.infinity,
      margin: compact
          ? const EdgeInsets.only(right: 12)
          : const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: preorderBorder),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PreOrderCoverImage(
                imageUrl: campaign.coverImageUrl,
                width: double.infinity,
                height: compact ? 105 : 150,
                borderRadius: 14,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE5D6),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'PRE-ORDER',
                      style: TextStyle(
                        color: Color(0xFFB85C3A),
                        fontSize: 10,
                        letterSpacing: .7,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (campaign.startingPrice > 0)
                    Text(
                      'From ${formatMoney(campaign.startingPrice)}',
                      style: const TextStyle(
                        color: preorderGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: onSellerTap,
                borderRadius: BorderRadius.circular(5),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    campaign.sellerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onSellerTap == null
                          ? preorderMuted
                          : preorderGreen,
                      fontSize: 13,
                      decoration: onSellerTap == null
                          ? null
                          : TextDecoration.underline,
                      decorationColor: preorderGreen,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                campaign.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: preorderText,
                  fontSize: 18,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              if (previews.isEmpty)
                const Text(
                  'Menu coming soon',
                  style: TextStyle(color: preorderMuted),
                )
              else
                ...previews.map(
                  (product) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '${product.name}  ${formatMoney(product.price)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: preorderText,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              if (compact) const Spacer() else const SizedBox(height: 8),
              const SizedBox(height: 8),
              Text(
                'Order by ${formatDateTime(campaign.orderCutoffAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: preorderMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Fulfilment ${formatDateTime(campaign.fulfilmentAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: preorderGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFFADB5B2),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
