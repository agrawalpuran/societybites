import 'package:flutter/material.dart';

import 'api_service.dart';
import 'session_service.dart';

/// Ensures the current user can create listings (seller role + UPI).
/// Shows a snackbar / dialog guidance when not ready.
class SellerOnboarding {
  /// Existing Start Selling confirmation + role enable. Used by Profile and Home.
  static Future<bool> startSelling(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start selling?'),
        content: const Text(
          'You will be able to list homemade food for neighbors in your society. '
          'You will need a UPI ID so buyers can pay you directly.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF0E5A47),
            ),
            child: const Text('Enable selling'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return false;
    await ApiService.updateMyProfile(role: 'seller');
    return true;
  }

  static Future<bool> ensureCanCreateListing(BuildContext context) async {
    try {
      final profile = await ApiService.getMe();
      await SessionService.cacheProfileFromApi(profile);

      final role = profile['role'] as String? ?? 'buyer';
      final upiId = (profile['upiId'] as String?)?.trim() ?? '';

      if (!context.mounted) return false;

      if (role != 'seller' && role != 'super_admin') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Enable selling first: Profile → Start Selling',
            ),
          ),
        );
        return false;
      }

      if (upiId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Add your UPI ID in Profile before creating a listing',
            ),
          ),
        );
        return false;
      }

      return true;
    } catch (e) {
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not verify seller profile: $e')),
      );
      return false;
    }
  }
}
