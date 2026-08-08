import 'package:flutter/material.dart';

import 'api_service.dart';
import 'session_service.dart';

/// Ensures the current user can create listings (seller role + UPI).
/// Shows a snackbar / dialog guidance when not ready.
class SellerOnboarding {
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
