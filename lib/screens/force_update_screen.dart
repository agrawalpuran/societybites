import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/force_update_service.dart';
import '../widgets/app_header.dart' show kAppDisplayName;

/// Blocking screen when the installed build is below the server minimum.
class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({super.key, required this.requirement});

  final ForceUpdateRequirement requirement;

  Future<void> _openUpdate() async {
    final raw = requirement.updateUrl.trim();
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final hasUrl = requirement.updateUrl.trim().isNotEmpty;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F9F8),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 40, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                const Icon(
                  Icons.system_update_alt_rounded,
                  size: 64,
                  color: Color(0xFF0E5A47),
                ),
                const SizedBox(height: 24),
                Text(
                  'Update required',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF101617),
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'This version of $kAppDisplayName can no longer connect to '
                  'our servers. Please install the latest build to continue.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    color: Color(0xFF6A7774),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Installed build ${requirement.currentBuild} · '
                  'Required ${requirement.minBuild}+',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF8A9491),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!hasUrl) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Open TestFlight (iOS) or your Play Store testing track '
                    '(Android) and install the newest SocietyEats build.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: Color(0xFF3A4644),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const Spacer(),
                if (hasUrl)
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _openUpdate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0E5A47),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Update now',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
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
