import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../web/web_breakpoints.dart';

const chefHuntSiteUrl = 'https://www.societyeats.com';

/// "Wing B" from a flat block. Empty blocks stay generic.
String chefHuntWingLabel(String? block) {
  final raw = block?.trim() ?? '';
  if (raw.isEmpty) return 'your wing';
  final lower = raw.toLowerCase();
  if (lower.startsWith('wing ') ||
      lower.startsWith('block ') ||
      lower.startsWith('tower ')) {
    return raw;
  }
  return 'Wing $raw';
}

const chefHuntEyebrow = 'COMMUNITY CHEF HUNT';

const chefHuntAndroidUrl =
    'https://play.google.com/store/apps/details?id=com.puran.societybites';

/// Text WhatsApp opens when the resident taps the hunt button.
String chefHuntInviteMessage({
  String? wingLabel,
  String? societyName,
}) {
  return 'Hello,\n\n'
      'SocietyEats is looking for a home chef in our society or neighbourhood. '
      'Nominate a home chef, or join yourself. '
      'SocietyEats will help you get your first order and provide full assistance with setup.\n\n'
      'Website: $chefHuntSiteUrl\n'
      'Android app: $chefHuntAndroidUrl\n'
      'iOS: Coming soon';
}

/// Peach nomination card. Shown at the bottom of Discovery after login.
class ChefHuntCard extends StatelessWidget {
  const ChefHuntCard({
    super.key,
    required this.wingLabel,
    this.societyName,
    this.onInvite,
  });

  final String wingLabel;
  final String? societyName;

  /// Test seam. Production opens WhatsApp with [chefHuntInviteMessage].
  final Future<void> Function(String message)? onInvite;

  Future<void> _invite(BuildContext context) async {
    final message = chefHuntInviteMessage(
      wingLabel: wingLabel,
      societyName: societyName,
    );
    if (onInvite != null) {
      await onInvite!(message);
      return;
    }
    final uri = Uri.https('wa.me', '/', {'text': message});
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFE3D2),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        chefHuntEyebrow,
                        style: TextStyle(
                          color: Color(0xFFE36B1A),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Know someone who makes amazing snacks or bakes?',
                        style: TextStyle(
                          color: webInk,
                          fontSize: 20,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const _WaveBadge(),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Nominate your neighbour chef or invite family in your society or outside. '
              'We help get them their first order and setup assistance.',
              style: TextStyle(fontSize: 13, height: 1.35, color: webMuted),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _invite(context),
                style: FilledButton.styleFrom(
                  backgroundColor: webGreenDark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: const StadiumBorder(),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _WhatsAppMark(),
                    SizedBox(width: 8),
                    Text('Invite via WhatsApp'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WhatsAppMark extends StatelessWidget {
  const _WhatsAppMark();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      size: Size.square(18),
      painter: _WhatsAppMarkPainter(),
    );
  }
}

class _WhatsAppMarkPainter extends CustomPainter {
  const _WhatsAppMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas.scale(scale);
    canvas.saveLayer(const Rect.fromLTWH(0, 0, 24, 24), Paint());
    final bubble = Path()
      ..addOval(Rect.fromCircle(center: const Offset(12, 11.6), radius: 8.4))
      ..moveTo(7.6, 17.2)
      ..quadraticBezierTo(6.4, 19.2, 4.5, 20.8)
      ..quadraticBezierTo(7.8, 20.1, 9.4, 18.2)
      ..close();
    canvas.drawPath(bubble, Paint()..color = Colors.white);
    final handset = Path()
      ..moveTo(9.15, 10.15)
      ..cubicTo(9.15, 9.15, 9.95, 8.55, 10.7, 8.95)
      ..lineTo(11.35, 9.5)
      ..cubicTo(11.7, 9.8, 11.7, 10.3, 11.4, 10.65)
      ..cubicTo(10.95, 11.25, 11.35, 11.95, 12.05, 12.6)
      ..cubicTo(12.75, 13.25, 13.45, 13.65, 14.1, 13.2)
      ..cubicTo(14.45, 12.95, 14.95, 12.95, 15.25, 13.25)
      ..lineTo(15.8, 13.85)
      ..cubicTo(16.2, 14.55, 15.65, 15.4, 14.6, 15.4)
      ..cubicTo(12.15, 15.4, 9.15, 12.45, 9.15, 10.15)
      ..close();
    canvas.drawPath(
      handset,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..blendMode = BlendMode.dstOut,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WaveBadge extends StatelessWidget {
  const _WaveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
        color: Color(0xFFE36B1A),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.waving_hand_rounded,
        color: Colors.white,
        size: 22,
      ),
    );
  }
}

