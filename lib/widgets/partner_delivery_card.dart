import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/data.dart';
import '../models/partner_delivery.dart';

class PartnerDeliveryCard extends StatelessWidget {
  const PartnerDeliveryCard({
    super.key,
    required this.delivery,
    required this.isSellerView,
    this.embedded = false,
    this.showHeadline = true,
    this.place,
  });

  final PartnerDelivery delivery;
  final bool isSellerView;
  final bool embedded;
  final bool showHeadline;
  final Widget? place;

  factory PartnerDeliveryCard.fromOrder({
    Key? key,
    required Order order,
    required bool isSellerView,
  }) {
    final delivery = order.partnerDelivery ?? const PartnerDelivery();
    return PartnerDeliveryCard(
      key: key ??
          ValueKey('partner-trip-${order.orderId}-${delivery.state}'),
      delivery: delivery,
      isSellerView: isSellerView,
      place: _placeForOrder(order, isSellerView: isSellerView),
    );
  }

  @override
  Widget build(BuildContext context) {
    final otp = (isSellerView ? delivery.pickupOtp : delivery.dropOtp)?.trim();
    final otpLabel = isSellerView ? 'Pickup OTP' : 'Delivery OTP';
    final showWaitAnimation =
        delivery.isWaitingForRider || (isSellerView && delivery.isInFlight);
    final lsp = (delivery.lspName ?? '').trim();
    final rider = (delivery.riderName ?? '').trim();
    final phone = (delivery.riderPhone ?? '').trim();
    final who = [lsp, rider, phone].where((part) => part.isNotEmpty).join(' · ');
    final trackUrl = (delivery.trackingUrl ?? '').trim();
    final failed = isSellerView &&
        (delivery.state ?? '').toLowerCase() == 'failed' &&
        (delivery.lastError ?? '').trim().isNotEmpty;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeadline)
          Row(
            children: [
              if (showWaitAnimation) ...[
                const PartnerWaitDots(key: ValueKey('partner-wait-dots')),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  delivery.stateLabel.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0B4F6C),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        if (place != null) ...[
          if (showHeadline) const SizedBox(height: 4),
          place!,
        ],
        if (delivery.isWaitingForRider) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const PartnerWaitDots(key: ValueKey('partner-wait-dots-line')),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  (delivery.state ?? '').toLowerCase() == 'retrying'
                      ? 'Retrying · searching again for a rider.'
                      : 'Looking for a nearby rider.',
                  style: const TextStyle(
                    color: Color(0xFF3A4644),
                    fontSize: 12,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (failed) ...[
          const SizedBox(height: 4),
          Text(
            delivery.lastError!.trim(),
            style: const TextStyle(
              color: Color(0xFF8A1C1C),
              fontSize: 12,
              height: 1.2,
            ),
          ),
        ],
        if (delivery.progressSteps.isNotEmpty) ...[
          SizedBox(height: showHeadline || delivery.isWaitingForRider ? 8 : 6),
          _PartnerProgressTrack(steps: delivery.progressSteps),
        ],
        if (who.isNotEmpty || (otp != null && otp.isNotEmpty)) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (who.isNotEmpty)
                Text(
                  who,
                  style: const TextStyle(
                    color: Color(0xFF1B2B34),
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (otp != null && otp.isNotEmpty)
                Text(
                  '$otpLabel $otp',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF101617),
                    fontSize: 13,
                    height: 1.2,
                    letterSpacing: 0.3,
                  ),
                ),
            ],
          ),
        ],
        if (trackUrl.isNotEmpty) ...[
          const SizedBox(height: 10),
          _TrackLink(url: trackUrl),
        ],
      ],
    );

    if (embedded) return body;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFC5D9E8)),
      ),
      child: body,
    );
  }
}

Widget _placeForOrder(Order order, {required bool isSellerView}) {
  if (isSellerView) {
    final parts = <String>[];
    final society = order.buyerSocietyName?.trim() ?? '';
    if (society.isNotEmpty) parts.add(society);
    final location = <String>[];
    final block = order.buyerBlock?.trim() ?? '';
    final flat = order.buyerFlatNumber?.trim() ?? '';
    if (block.isNotEmpty) location.add('Block $block');
    if (flat.isNotEmpty) location.add('Flat $flat');
    if (location.isNotEmpty) parts.add(location.join(', '));
    final place = parts.join(' · ');
    final distance = order.approxDistanceLabel;
    const style = TextStyle(
      color: Color(0xFF3A4644),
      fontSize: 13,
      height: 1.2,
    );
    if (place.isEmpty && distance.isEmpty) return const SizedBox.shrink();
    if (distance.isEmpty) return Text(place, style: style);
    return Text.rich(
      TextSpan(
        children: [
          if (place.isNotEmpty) TextSpan(text: place),
          TextSpan(text: place.isEmpty ? distance : '  $distance'),
        ],
      ),
      style: style,
    );
  }
  final society = (order.sellerSocietyName ?? '').trim();
  if (society.isEmpty) return const SizedBox.shrink();
  return Text(
    'Seller Society: $society',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      color: Color(0xFF3A4644),
      fontSize: 13,
      height: 1.2,
    ),
  );
}

class PartnerWaitDots extends StatefulWidget {
  const PartnerWaitDots({super.key});

  @override
  State<PartnerWaitDots> createState() => _PartnerWaitDotsState();
}

class _PartnerWaitDotsState extends State<PartnerWaitDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return SizedBox(
          width: 28,
          height: 10,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 3; i++) _dot(i),
            ],
          ),
        );
      },
    );
  }

  Widget _dot(int index) {
    final t = (_controller.value + index / 3) % 1.0;
    final wave = (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
    return Opacity(
      opacity: 0.3 + 0.7 * wave,
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: Color(0xFF0B4F6C),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _TrackLink extends StatelessWidget {
  const _TrackLink({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0B4F6C),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => openPartnerTrackingUrl(context, url),
        borderRadius: BorderRadius.circular(10),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.map_outlined,
                size: 16,
                color: Colors.white,
              ),
              SizedBox(width: 6),
              Text(
                'Live tracking',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> openPartnerTrackingUrl(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tracking link copied')),
    );
  }
}

class _PartnerProgressTrack extends StatelessWidget {
  const _PartnerProgressTrack({required this.steps});

  final List<PartnerProgressStep> steps;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  height: 2,
                  color: steps[i].kind == PartnerProgressKind.upcoming
                      ? const Color(0xFFC5D9E8)
                      : const Color(0xFF0B4F6C),
                ),
              ),
            ),
          _PartnerProgressDot(step: steps[i]),
        ],
      ],
    );
  }
}

class _PartnerProgressDot extends StatelessWidget {
  const _PartnerProgressDot({required this.step});

  final PartnerProgressStep step;

  @override
  Widget build(BuildContext context) {
    final done = step.kind == PartnerProgressKind.done;
    final current = step.kind == PartnerProgressKind.current;
    final color = step.kind == PartnerProgressKind.upcoming
        ? const Color(0xFF8AA0AE)
        : const Color(0xFF0B4F6C);
    final marker = Container(
      width: current ? 9 : 8,
      height: current ? 9 : 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done || current ? const Color(0xFF0B4F6C) : Colors.white,
        border: Border.all(color: color, width: 1.5),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (current) _PartnerPulseHalo(child: marker) else marker,
        const SizedBox(height: 3),
        Text(
          step.label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: current || done ? FontWeight.w700 : FontWeight.w500,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class _PartnerPulseHalo extends StatefulWidget {
  const _PartnerPulseHalo({required this.child});

  final Widget child;

  @override
  State<_PartnerPulseHalo> createState() => _PartnerPulseHaloState();
}

class _PartnerPulseHaloState extends State<_PartnerPulseHalo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.fromRGBO(11, 79, 108, 0.18 * _controller.value),
          ),
          child: Transform.scale(
            scale: 0.88 + 0.14 * _controller.value,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
