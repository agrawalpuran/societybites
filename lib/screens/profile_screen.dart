import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/legal_documents.dart';
import '../models/seller_fulfilment.dart';
import '../models/seller_payment_preference.dart';
import '../models/seller_terms.dart';
import '../models/selling_reach.dart';
import '../services/api_service.dart';
import '../services/profile_photo_processor.dart';
import '../services/seller_onboarding.dart';
import '../services/session_service.dart';
import '../services/push_notification_service.dart';
import '../widgets/app_header.dart';
import '../widgets/confirm_upi_id_dialog.dart';
import '../widgets/photo_source_sheet.dart';
import '../widgets/profile_menu_tile.dart';
import '../widgets/seller_avatar.dart';
import 'admin/admin_shell_screen.dart';
import 'guest_landing_screen.dart';
import 'help_center_screen.dart';
import 'legal_screen.dart';
import 'login_screen.dart';
import 'profile_photo_crop_screen.dart';
import 'seller_settings_screen.dart';
import 'seller_terms_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.onSelectTab,
    this.fetchProfile,
    this.updateProfile,
    this.saveUpiDetails,
    this.saveFssaiDetails,
    this.deleteAccount,
    this.pickProfilePhotoBytes,
    this.cropProfilePhoto,
    this.uploadProfilePhoto,
    this.saveProfilePhoto,
    this.startSelling,
    this.acceptSellerTerms,
  });

  /// Switches the main shell tab instead of pushing a new route.
  final ValueChanged<int>? onSelectTab;

  /// Test seam. Production uses [ApiService.getMe].
  final Future<Map<String, dynamic>> Function()? fetchProfile;

  /// Test seam. Production uses [ApiService.updateMyProfile].
  final Future<Map<String, dynamic>> Function({
    String? sellingReachLevel,
    String? fulfilmentMode,
    double? deliveryCharge,
    double? deliveryChargeInSociety,
    double? deliveryChargeNearby,
    double? deliveryChargeExtended,
    String? paymentPreference,
  })? updateProfile;

  /// Test seam. Production uses [ApiService.updateMyProfile] for UPI.
  final Future<void> Function({
    required String upiId,
    String? upiDisplayName,
  })? saveUpiDetails;

  /// Test seam. Production uses [ApiService.updateMyProfile] for FSSAI.
  final Future<void> Function({
    required String fssaiNumber,
    String? fssaiRegisteredName,
    String? fssaiExpiry,
  })? saveFssaiDetails;

  /// Test seam. Production uses [ApiService.deleteMyAccount].
  final Future<void> Function()? deleteAccount;

  /// Test seams for profile photo. Production uses camera/gallery + crop + upload.
  final Future<Uint8List?> Function(ImageSource source)? pickProfilePhotoBytes;
  final Future<Uint8List?> Function(Uint8List bytes)? cropProfilePhoto;
  final Future<Map<String, dynamic>> Function(List<int> bytes)?
      uploadProfilePhoto;
  final Future<Map<String, dynamic>> Function({String? profilePhotoUrl})?
      saveProfilePhoto;

  /// Test seam. Production uses [SellerOnboarding.startSelling].
  final Future<bool> Function(BuildContext context)? startSelling;

  /// Test seam. Production uses [ApiService.acceptSellerTerms].
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> body)?
      acceptSellerTerms;

  @override
  ProfileScreenState createState() => ProfileScreenState();
}

enum _ProfileEditAction { displayName, changePhoto, removePhoto }

class ProfileScreenState extends State<ProfileScreen> {
  String? _name;
  String? _phone;
  String? _role;
  String? _societyName;
  String? _flatNumber;
  String? _upiId;
  bool _deletingAccount = false;
  String? _upiDisplayName;
  SellingReachLevel _sellingReachLevel = SellingReachLevel.mySociety;
  SellingReach _sellingReach = const SellingReach();
  SellerFulfilment _fulfilment = const SellerFulfilment();
  SellerPaymentPreference _paymentPreference = defaultSellerPaymentPreference;
  String? _fssaiNumber;
  String? _profilePhotoUrl;
  bool _savingProfilePhoto = false;
  String? _fssaiRegisteredName;
  DateTime? _fssaiExpiry;
  final _sellerSettingsTick = ValueNotifier(0);
  _PendingSellerEnable? _pendingSellerEnable;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _sellerSettingsTick.dispose();
    super.dispose();
  }

  void _refreshSellerSettings() {
    _sellerSettingsTick.value++;
  }

  Future<void> reload() => _loadProfile();

  Future<void> _readSessionCache() async {
    _phone = await SessionService.getPhone();
    _name = await SessionService.getUserName();
    _role = await SessionService.getRole();
    _societyName = await SessionService.getSocietyName();
    _flatNumber = await SessionService.getFlatNumber();
  }

  Future<void> _loadProfile() async {
    await _readSessionCache();
    if (mounted) setState(() {});

    final userId = await SessionService.getUserId();
    if (userId != null) {
      try {
        final profile = widget.fetchProfile != null
            ? await widget.fetchProfile!()
            : await ApiService.getMe();
        try {
          await SessionService.cacheProfileFromApi(profile);
        } catch (_) {}
        _name = profile['name'] as String? ?? _name;
        _role = profile['role'] as String? ?? _role;
        _phone = profile['phone'] as String? ?? _phone;
        _upiId = profile['upiId'] as String? ?? _upiId;
        _upiDisplayName =
            profile['upiDisplayName'] as String? ?? _upiDisplayName;
        final society = _asStringKeyedMap(profile['society']);
        final flat = _asStringKeyedMap(profile['flat']);
        _societyName = society?['name'] as String? ?? _societyName;
        _flatNumber = flat?['flatNumber'] as String? ?? _flatNumber;
        _sellingReachLevel = parseSellingReachLevel(profile['sellingReachLevel']);
        _sellingReach = SellingReach.fromAuthMe(profile);
        _fulfilment = SellerFulfilment.fromAuthMe(profile);
        _paymentPreference = paymentPreferenceFromAuthMe(profile);
        _applyFssaiFromProfile(profile);
        _profilePhotoUrl = profile['profilePhotoUrl'] as String? ?? _profilePhotoUrl;
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {});
    _refreshSellerSettings();
  }

  String get _displayName {
    if (_name != null && _name!.isNotEmpty) return _name!;
    if (_phone != null && _phone!.length >= 4) {
      return 'Member ••••${_phone!.substring(_phone!.length - 4)}';
    }
    return 'SocietyBites Member';
  }

  String get _roleLabel {
    switch (_role) {
      case 'seller':
        return 'Seller';
      case 'buyer':
        return 'Buyer';
      default:
        return 'Resident';
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You will need to verify your phone number again to sign back in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFD94F4F),
            ),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final authProvider = await SessionService.getAuthProvider();
    await PushNotificationService.unregister();
    if (authProvider == '2factor') {
      await ApiService.logoutTwoFactor();
    }
    await SessionService.clear();
    if (authProvider == 'firebase') {
      await FirebaseAuth.instance.signOut();
    }

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _confirmDeleteAccount() async {
    if (_deletingAccount) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'Your account and associated personal data will be permanently '
          'deleted. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFD94F4F),
            ),
            child: const Text('Delete Account'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _deleteAccount();
  }

  Future<void> _deleteAccount() async {
    if (_deletingAccount) return;
    setState(() => _deletingAccount = true);

    try {
      if (widget.deleteAccount != null) {
        await widget.deleteAccount!();
      } else {
        await ApiService.deleteMyAccount();
      }

      if (!mounted) return;

      final authProvider = await SessionService.getAuthProvider();
      // Clear local auth first so a deleted account cannot be restored if a
      // later cleanup step fails or hangs.
      await SessionService.clear();
      try {
        await PushNotificationService.unregister();
      } catch (_) {}
      if (authProvider == '2factor') {
        try {
          await ApiService.logoutTwoFactor();
        } catch (_) {}
      }
      if (authProvider == 'firebase') {
        try {
          await FirebaseAuth.instance.signOut();
        } catch (_) {}
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your account has been deleted.')),
      );

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const GuestLandingScreen()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingAccount = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    }
  }

  Future<void> openSellerSettingsAfterEnable() async {
    await _loadProfile();
    if (!mounted) return;
    _openSellerSettings(firstTime: true);
  }

  void _openSellerSettings({bool firstTime = false}) {
    if (firstTime) {
      _pendingSellerEnable = _PendingSellerEnable()
        ..paymentPreference = defaultSellerPaymentPreference.apiValue;
      _paymentPreference = defaultSellerPaymentPreference;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ValueListenableBuilder<int>(
          valueListenable: _sellerSettingsTick,
          builder: (context, _, child) {
            final holdingSetup = firstTime && _pendingSellerEnable != null;
            return SellerSettingsScreen(
              isFirstTimeSetup: holdingSetup,
              upiSubtitle: (_upiId != null && _upiId!.isNotEmpty)
                  ? _upiId!
                  : 'Add UPI ID so buyers can pay you',
              paymentTitle: _paymentPreference.title,
              sellingReachSubtitle:
                  _sellingReach.subtitleFor(_sellingReachLevel),
              fulfilmentTitle: _fulfilment.mode.title,
              fulfilmentSubtitle: _fulfilment.subtitle,
              fssaiSubtitle: _fssaiSubtitle,
              onEditUpi: () => _editUpi(),
              onChangePaymentPreference: _changePaymentPreference,
              onChangeSellingReach: _changeSellingReach,
              onChangeFulfilment: _changeFulfilment,
              onEditFssai: _editFssai,
              onSaveAndEnable: holdingSetup ? _saveAndEnableSelling : null,
            );
          },
        ),
      ),
    ).then((_) async {
      if (!mounted || _pendingSellerEnable == null) return;
      _pendingSellerEnable = null;
      await _loadProfile();
    });
  }

  Future<void> _openProfileEditor() async {
    final action = await showModalBottomSheet<_ProfileEditAction>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Edit Profile',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF101617),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('Change display name'),
                onTap: () => Navigator.pop(
                  context,
                  _ProfileEditAction.displayName,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.add_a_photo_outlined),
                title: const Text('Change profile photo'),
                onTap: () => Navigator.pop(
                  context,
                  _ProfileEditAction.changePhoto,
                ),
              ),
              if (_profilePhotoUrl != null)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFD94F4F),
                  ),
                  title: const Text('Remove profile photo'),
                  onTap: () => Navigator.pop(
                    context,
                    _ProfileEditAction.removePhoto,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _ProfileEditAction.displayName:
        await _editProfile();
      case _ProfileEditAction.changePhoto:
        await _changeProfilePhoto();
      case _ProfileEditAction.removePhoto:
        await _removeProfilePhoto();
    }
  }

  Future<void> _editProfile() async {
    final nameController = TextEditingController(text: _name ?? '');
    final newName = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            24 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Edit Profile',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101617),
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Name',
                  filled: true,
                  fillColor: const Color(0xFFF5F7F6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE0E5E3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE0E5E3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF0E5A47)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.pop(ctx, nameController.text.trim()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0E5A47),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (newName == null || newName.isEmpty || !mounted) return;

    try {
      await ApiService.updateMyProfile(name: newName);
      await SessionService.saveUserName(newName);
      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update profile: $e')));
    }
  }

  Future<void> _editUpi({bool afterEnableSelling = false}) async {
    final upiController = TextEditingController(text: _upiId ?? '');
    final nameController = TextEditingController(
      text: _upiDisplayName ?? _name ?? '',
    );
    String? errorText;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                24 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    afterEnableSelling
                        ? 'Add UPI to receive payments'
                        : 'UPI for Payments',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF101617),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    afterEnableSelling
                        ? 'Selling is on. Add your UPI ID so buyers can pay you for orders.'
                        : 'Buyers will pay this UPI ID when they order your food.',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6A7774),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: upiController,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'UPI ID',
                      hintText: 'yourname@oksbi',
                      errorText: errorText,
                      filled: true,
                      fillColor: const Color(0xFFF5F7F6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE0E5E3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE0E5E3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFF0E5A47)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'Display name on UPI (optional)',
                      filled: true,
                      fillColor: const Color(0xFFF5F7F6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE0E5E3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE0E5E3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFF0E5A47)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () async {
                        final upi = upiController.text.trim();
                        if (upi.isEmpty || !upi.contains('@')) {
                          setSheetState(() {
                            errorText =
                                'Enter a valid UPI ID (e.g. name@oksbi)';
                          });
                          return;
                        }
                        final confirmed = await confirmUpiIdBeforeSave(
                          ctx,
                          upiId: upi,
                        );
                        if (confirmed && ctx.mounted) {
                          Navigator.pop(ctx, true);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0E5A47),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Save UPI',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (saved != true || !mounted) {
      upiController.dispose();
      nameController.dispose();
      return;
    }

    final upi = upiController.text.trim();
    final displayName = nameController.text.trim();
    upiController.dispose();
    nameController.dispose();

    final pending = _pendingSellerEnable;
    if (pending != null) {
      setState(() {
        _upiId = upi;
        _upiDisplayName = displayName.isEmpty ? null : displayName;
        pending
          ..includeUpi = true
          ..upiId = upi
          ..upiDisplayName = displayName.isEmpty ? null : displayName;
      });
      _refreshSellerSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('UPI ID saved')),
      );
      return;
    }

    try {
      if (widget.saveUpiDetails != null) {
        await widget.saveUpiDetails!(
          upiId: upi,
          upiDisplayName: displayName.isEmpty ? null : displayName,
        );
      } else {
        await ApiService.updateMyProfile(
          upiId: upi,
          upiDisplayName: displayName.isEmpty ? null : displayName,
        );
      }
      await _loadProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            afterEnableSelling
                ? 'You can sell now — add a listing from Dashboard'
                : 'UPI ID saved',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save UPI: $e')));
    }
  }

  Map<String, dynamic>? _asStringKeyedMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  void _applyFssaiFromProfile(Map<String, dynamic> profile) {
    final fssai = _asStringKeyedMap(profile['fssai']);
    if (fssai == null) return;
    final number = fssai['number']?.toString().trim();
    if (number != null && number.isNotEmpty && number != 'null') {
      _fssaiNumber = number;
    }
    final registeredName = fssai['registeredName']?.toString().trim();
    if (registeredName != null &&
        registeredName.isNotEmpty &&
        registeredName != 'null') {
      _fssaiRegisteredName = registeredName;
    }
    final expiryRaw = fssai['expiry']?.toString().trim();
    if (expiryRaw != null && expiryRaw.isNotEmpty && expiryRaw != 'null') {
      if (expiryRaw.length >= 10) {
        final year = int.tryParse(expiryRaw.substring(0, 4));
        final month = int.tryParse(expiryRaw.substring(5, 7));
        final day = int.tryParse(expiryRaw.substring(8, 10));
        if (year != null && month != null && day != null) {
          _fssaiExpiry = DateTime(year, month, day);
        }
      } else {
        _fssaiExpiry = DateTime.tryParse(expiryRaw)?.toLocal() ?? _fssaiExpiry;
      }
    }
  }

  String get _fssaiSubtitle {
    if (_fssaiNumber == null || _fssaiNumber!.isEmpty) {
      return 'Add your 14-digit FSSAI Registration Number';
    }
    final parts = <String>[_fssaiNumber!];
    if (_fssaiRegisteredName != null && _fssaiRegisteredName!.isNotEmpty) {
      parts.add(_fssaiRegisteredName!);
    }
    if (_fssaiExpiry != null) {
      final expiry = _fssaiExpiry!;
      parts.add(
        'Exp ${expiry.day.toString().padLeft(2, '0')}/${expiry.month.toString().padLeft(2, '0')}/${expiry.year}',
      );
    }
    return parts.join(' · ');
  }

  Future<void> _editFssai() async {
    final numberController = TextEditingController(text: _fssaiNumber ?? '');
    final nameController = TextEditingController(
      text: _fssaiRegisteredName ?? '',
    );
    DateTime? expiry = _fssaiExpiry;
    String? errorText;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            String expiryLabel = 'Optional';
            if (expiry != null) {
              expiryLabel =
                  '${expiry!.day.toString().padLeft(2, '0')}/${expiry!.month.toString().padLeft(2, '0')}/${expiry!.year}';
            }
            return Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                24 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'FSSAI details',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF101617),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    (_fssaiNumber != null && _fssaiNumber!.isNotEmpty)
                        ? 'Saved licence $_fssaiNumber. You can update the details below.'
                        : 'Existing sellers can add or update their licence here. This is stored for records only — not verified yet.',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6A7774),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: numberController,
                    keyboardType: TextInputType.number,
                    maxLength: 14,
                    decoration: InputDecoration(
                      labelText: 'FSSAI registration number',
                      hintText: '14 digits',
                      errorText: errorText,
                      filled: true,
                      fillColor: const Color(0xFFF5F7F6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE0E5E3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE0E5E3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFF0E5A47)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'Registered name (optional)',
                      filled: true,
                      fillColor: const Color(0xFFF5F7F6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE0E5E3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE0E5E3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFF0E5A47)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Expiry date'),
                    subtitle: Text(expiryLabel),
                    trailing: TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: expiry ?? DateTime.now(),
                          firstDate: DateTime(2015),
                          lastDate: DateTime.now().add(const Duration(days: 3650)),
                        );
                        if (picked != null) {
                          setSheetState(() => expiry = picked);
                        }
                      },
                      child: const Text('Choose'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () {
                        final digits = numberController.text.replaceAll(
                          RegExp(r'\D'),
                          '',
                        );
                        if (digits.isNotEmpty && digits.length != 14) {
                          setSheetState(
                            () => errorText = 'Enter a 14-digit FSSAI number',
                          );
                          return;
                        }
                        Navigator.pop(ctx, true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0E5A47),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Save',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (saved != true || !mounted) {
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        numberController.dispose();
        nameController.dispose();
      });
      return;
    }

    final number = numberController.text.replaceAll(RegExp(r'\D'), '');
    final registeredName = nameController.text.trim();
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      numberController.dispose();
      nameController.dispose();
    });
    final expiryIso = expiry == null
        ? ''
        : '${expiry!.year.toString().padLeft(4, '0')}-${expiry!.month.toString().padLeft(2, '0')}-${expiry!.day.toString().padLeft(2, '0')}';

    final pending = _pendingSellerEnable;
    if (pending != null) {
      setState(() {
        _fssaiNumber = number.isEmpty ? _fssaiNumber : number;
        _fssaiRegisteredName =
            registeredName.isEmpty ? _fssaiRegisteredName : registeredName;
        _fssaiExpiry = expiry ?? _fssaiExpiry;
        pending
          ..includeFssai = true
          ..fssaiNumber = number
          ..fssaiRegisteredName = registeredName.isEmpty ? null : registeredName
          ..fssaiExpiry = expiryIso.isEmpty ? null : expiryIso;
      });
      _refreshSellerSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('FSSAI details saved')),
      );
      return;
    }

    try {
      if (widget.saveFssaiDetails != null) {
        await widget.saveFssaiDetails!(
          fssaiNumber: number,
          fssaiRegisteredName: registeredName,
          fssaiExpiry: expiryIso,
        );
      } else {
        final updated = await ApiService.updateMyProfile(
          fssaiNumber: number,
          fssaiRegisteredName: registeredName.isEmpty ? null : registeredName,
          fssaiExpiry: expiryIso.isEmpty ? null : expiryIso,
        );
        _applyFssaiFromProfile(updated);
      }
      if (!mounted) return;
      setState(() {
        _fssaiNumber = number.isEmpty ? _fssaiNumber : number;
        _fssaiRegisteredName =
            registeredName.isEmpty ? _fssaiRegisteredName : registeredName;
        _fssaiExpiry = expiry ?? _fssaiExpiry;
      });
      await _loadProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('FSSAI details saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save FSSAI details: $e')),
      );
    }
  }

  Future<void> _enableSelling() async {
    try {
      final enabled = widget.startSelling != null
          ? await widget.startSelling!(context)
          : await SellerOnboarding.startSelling(context);
      if (!enabled || !mounted) return;
      await openSellerSettingsAfterEnable();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not enable selling: $e')));
    }
  }

  Future<void> _saveAndEnableSelling() async {
    final pending = _pendingSellerEnable;
    if (pending == null || !mounted) return;
    final accepted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const SellerTermsScreen()),
    );
    if (accepted != true || !mounted) return;
    try {
      final body = pending.toJson();
      final updated = widget.acceptSellerTerms != null
          ? await widget.acceptSellerTerms!(body)
          : await ApiService.acceptSellerTerms(body);
      if (!mounted) return;
      try {
        await SessionService.cacheProfileFromApi(updated);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _applySellerEnableResult(updated);
        _pendingSellerEnable = null;
      });
      _refreshSellerSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selling enabled')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not enable selling: $e')),
      );
    }
  }

  void _applySellerEnableResult(Map<String, dynamic> updated) {
    _role = updated['role'] as String? ?? 'seller';
    if (updated.containsKey('upiId')) {
      _upiId = updated['upiId'] as String?;
    }
    if (updated.containsKey('upiDisplayName')) {
      _upiDisplayName = updated['upiDisplayName'] as String?;
    }
    if (updated.containsKey('paymentPreference')) {
      _paymentPreference = paymentPreferenceFromAuthMe(updated);
    }
    if (updated.containsKey('sellingReachLevel')) {
      _sellingReachLevel = parseSellingReachLevel(updated['sellingReachLevel']);
    }
    if (updated.containsKey('sellingReach') || updated.containsKey('cityKey')) {
      _sellingReach = SellingReach.fromAuthMe(updated);
    }
    if (updated.containsKey('fulfilmentMode') || updated.containsKey('fulfilment')) {
      _fulfilment = SellerFulfilment.fromAuthMe(updated);
    }
    _applyFssaiFromProfile(updated);
  }

  Future<void> _changeProfilePhoto() async {
    if (_savingProfilePhoto) return;
    final source = await showPhotoSourceSheet(
      context,
      title: 'Change Profile Photo',
    );
    if (source == null || !mounted) return;

    try {
      Uint8List? picked;
      if (widget.pickProfilePhotoBytes != null) {
        picked = await widget.pickProfilePhotoBytes!(source);
      } else {
        final picker = ImagePicker();
        final file = await picker.pickImage(
          source: source,
          maxWidth: 2000,
          imageQuality: 90,
        );
        if (file != null) {
          picked = await file.readAsBytes();
        }
      }
      if (picked == null || !mounted) return;

      Uint8List? cropped;
      if (widget.cropProfilePhoto != null) {
        cropped = await widget.cropProfilePhoto!(picked);
      } else {
        cropped = await Navigator.push<Uint8List>(
          context,
          MaterialPageRoute(
            builder: (_) => ProfilePhotoCropScreen(imageBytes: picked!),
          ),
        );
      }
      if (cropped == null || !mounted) return;

      setState(() => _savingProfilePhoto = true);
      _refreshSellerSettings();
      final encoded = encodeProfilePhoto(cropped);
      final profile = widget.uploadProfilePhoto != null
          ? await widget.uploadProfilePhoto!(encoded)
          : await ApiService.uploadMyProfilePhoto(bytes: encoded);
      if (!mounted) return;
      setState(() {
        _profilePhotoUrl = profile['profilePhotoUrl'] as String?;
        _savingProfilePhoto = false;
      });
      _refreshSellerSettings();
    } on ProfilePhotoRejected catch (error) {
      if (!mounted) return;
      setState(() => _savingProfilePhoto = false);
      _refreshSellerSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _savingProfilePhoto = false);
      _refreshSellerSettings();
      final denied = error.code.toLowerCase().contains('denied') ||
          (error.message?.toLowerCase().contains('denied') ?? false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            denied
                ? (source == ImageSource.camera
                    ? 'Camera access is needed to take a photo. You can enable it in Settings.'
                    : 'Photo access is needed to choose from your gallery. You can enable it in Settings.')
                : 'Could not open ${source == ImageSource.camera ? 'the camera' : 'the gallery'}. Please try again.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _savingProfilePhoto = false);
      _refreshSellerSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ApiService.userFacingError(error).contains('too large')
                ? profilePhotoTooLargeMessage
                : 'Could not save your photo. Please try again.',
          ),
        ),
      );
    }
  }

  Future<void> _removeProfilePhoto() async {
    if (_savingProfilePhoto) return;
    setState(() => _savingProfilePhoto = true);
    _refreshSellerSettings();
    try {
      final profile = widget.saveProfilePhoto != null
          ? await widget.saveProfilePhoto!(profilePhotoUrl: null)
          : await ApiService.updateMyProfile(profilePhotoUrl: null);
      if (!mounted) return;
      setState(() {
        _profilePhotoUrl = profile['profilePhotoUrl'] as String?;
        _savingProfilePhoto = false;
      });
      _refreshSellerSettings();
    } catch (_) {
      if (!mounted) return;
      setState(() => _savingProfilePhoto = false);
      _refreshSellerSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove your photo. Please try again.')),
      );
    }
  }

  bool get _isSeller => _role == 'seller' || _role == 'super_admin';

  Future<void> _changeSellingReach() async {
    final selected = await showModalBottomSheet<SellingReachLevel>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Selling Reach',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101617),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Who can see your food?',
                style: TextStyle(fontSize: 14, color: Color(0xFF6A7774)),
              ),
              const SizedBox(height: 18),
              ...SellingReachLevel.values.map((level) {
                final enabled = _sellingReach.isSelectable(level);
                final selected = level == _sellingReachLevel;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: const Color(0xFFF5F7F6),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: enabled ? () => Navigator.pop(ctx, level) : null,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Icon(
                              selected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: enabled
                                  ? const Color(0xFF0E5A47)
                                  : const Color(0xFFADB5B2),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    level.title,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: enabled
                                          ? const Color(0xFF101617)
                                          : const Color(0xFF8A9491),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _sellingReach.optionSubtitleFor(level),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: enabled
                                          ? const Color(0xFF6A7774)
                                          : const Color(0xFF8A9491),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );

    if (selected == null || !mounted || selected == _sellingReachLevel) return;

    final pending = _pendingSellerEnable;
    if (pending != null) {
      setState(() {
        _sellingReachLevel = selected;
        pending.sellingReachLevel = selected.apiValue;
      });
      _refreshSellerSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selling reach updated')),
      );
      return;
    }

    final previous = _sellingReachLevel;
    try {
      final updated = widget.updateProfile != null
          ? await widget.updateProfile!(sellingReachLevel: selected.apiValue)
          : await ApiService.updateMyProfile(
              sellingReachLevel: selected.apiValue,
            );
      if (!mounted) return;
      setState(() {
        _sellingReachLevel = parseSellingReachLevel(updated['sellingReachLevel']);
        if (updated.containsKey('sellingReach') || updated.containsKey('cityKey')) {
          _sellingReach = SellingReach.fromAuthMe(updated);
        }
      });
      _refreshSellerSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selling reach updated')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sellingReachLevel = previous);
      _refreshSellerSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update selling reach: $e')),
      );
    }
  }

  Future<void> _changeFulfilment() async {
    final saved = await showModalBottomSheet<_FulfilmentDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: _FulfilmentSheet(initial: _fulfilment),
      ),
    );

    if (saved == null || !mounted) return;

    double? parseCharge(String raw, String label) {
      if (!saved.mode.showsDeliveryCharge) return 0;
      final charge = raw.trim().isEmpty ? 0.0 : double.tryParse(raw.trim());
      if (charge == null || charge < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enter a valid $label of ₹0 or more')),
        );
        return null;
      }
      return charge;
    }

    final inSociety = parseCharge(saved.inSocietyText, 'in-society delivery charge');
    if (inSociety == null) return;
    final nearby = parseCharge(saved.nearbyText, 'nearby delivery charge');
    if (nearby == null) return;
    final extended = parseCharge(saved.extendedText, 'extended delivery charge');
    if (extended == null) return;
    final draftMode = saved.mode;

    final pending = _pendingSellerEnable;
    if (pending != null) {
      setState(() {
        _fulfilment = SellerFulfilment(
          mode: draftMode,
          deliveryCharge: nearby,
          deliveryChargeInSociety: inSociety,
          deliveryChargeNearby: nearby,
          deliveryChargeExtended: extended,
        );
        pending
          ..includeFulfilment = true
          ..fulfilmentMode = draftMode.apiValue
          ..deliveryCharge = nearby
          ..deliveryChargeInSociety = inSociety
          ..deliveryChargeNearby = nearby
          ..deliveryChargeExtended = extended;
      });
      _refreshSellerSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fulfilment updated')),
      );
      return;
    }

    final previous = _fulfilment;
    try {
      final updated = widget.updateProfile != null
          ? await widget.updateProfile!(
              fulfilmentMode: draftMode.apiValue,
              deliveryCharge: nearby,
              deliveryChargeInSociety: inSociety,
              deliveryChargeNearby: nearby,
              deliveryChargeExtended: extended,
            )
          : await ApiService.updateMyProfile(
              fulfilmentMode: draftMode.apiValue,
              deliveryCharge: nearby,
              deliveryChargeInSociety: inSociety,
              deliveryChargeNearby: nearby,
              deliveryChargeExtended: extended,
            );
      if (!mounted) return;
      setState(() => _fulfilment = SellerFulfilment.fromAuthMe(updated));
      _refreshSellerSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fulfilment updated')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _fulfilment = previous);
      _refreshSellerSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update fulfilment: $e')),
      );
    }
  }

  Future<void> _changePaymentPreference() async {
    final selected = await showModalBottomSheet<SellerPaymentPreference>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _PaymentPreferenceSheet(initial: _paymentPreference),
    );

    if (selected == null || !mounted || selected == _paymentPreference) return;

    final pending = _pendingSellerEnable;
    if (pending != null) {
      setState(() {
        _paymentPreference = selected;
        pending.paymentPreference = selected.apiValue;
      });
      _refreshSellerSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment methods updated')),
      );
      return;
    }

    final previous = _paymentPreference;
    try {
      final updated = widget.updateProfile != null
          ? await widget.updateProfile!(paymentPreference: selected.apiValue)
          : await ApiService.updateMyProfile(paymentPreference: selected.apiValue);
      if (!mounted) return;
      setState(() {
        _paymentPreference = paymentPreferenceFromAuthMe(updated);
      });
      _refreshSellerSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment methods updated')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _paymentPreference = previous);
      _refreshSellerSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update payment methods: $e')),
      );
    }
  }

  void _openLegal(String title, String content) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LegalScreen(title: title, content: content),
      ),
    );
  }

  void _showAbout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'SocietyBites',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF0E5A47),
          ),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version 1.0.0',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF3A4644),
              ),
            ),
            SizedBox(height: 12),
            Text(
              'A hyperlocal food marketplace for gated communities.',
              style: TextStyle(color: Color(0xFF6A7774), height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Close',
              style: TextStyle(color: Color(0xFF0E5A47)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF0E5A47),
          onRefresh: _loadProfile,
          child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    const AppHeader(),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'My Profile',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF101617),
                            ),
                          ),
                          const SizedBox(height: 20),
                          _ProfileCard(
                            name: _displayName,
                            phone: _phone,
                            role: _roleLabel,
                            societyName: _societyName,
                            flatNumber: _flatNumber,
                            photoUrl: _profilePhotoUrl,
                            onEdit: _openProfileEditor,
                          ),
                          if (_role == 'buyer' ||
                              _role == null ||
                              _role == 'super_admin') ...[
                            const SizedBox(height: 24),
                            const Text(
                              'ACCOUNT',
                              style: TextStyle(
                                fontSize: 12,
                                letterSpacing: 1.4,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF8A9491),
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (_role == 'buyer' || _role == null)
                              ProfileMenuTile(
                                icon: Icons.storefront_rounded,
                                title: 'Start Selling',
                                subtitle:
                                    'List food for neighbors in your society',
                                onTap: _enableSelling,
                              ),
                            if (_role == 'super_admin')
                              ProfileMenuTile(
                                icon: Icons.admin_panel_settings_rounded,
                                title: 'Admin Portal',
                                subtitle: 'Manage platform settings',
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const AdminShellScreen(),
                                    ),
                                  );
                                },
                              ),
                          ],
                          if (_isSeller) ...[
                            const SizedBox(height: 20),
                            const Text(
                              'SELLER',
                              style: TextStyle(
                                fontSize: 12,
                                letterSpacing: 1.4,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF8A9491),
                              ),
                            ),
                            const SizedBox(height: 10),
                            ProfileMenuTile(
                              icon: Icons.settings_outlined,
                              title: 'Seller Settings',
                              subtitle:
                                  'Manage payments, fulfilment & FSSAI',
                              onTap: _openSellerSettings,
                            ),
                          ],
                          const SizedBox(height: 20),
                          const Text(
                            'SUPPORT',
                            style: TextStyle(
                              fontSize: 12,
                              letterSpacing: 1.4,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF8A9491),
                            ),
                          ),
                          const SizedBox(height: 10),
                          ProfileMenuTile(
                            icon: Icons.help_outline_rounded,
                            title: 'Help Center',
                            subtitle: 'FAQs and community support',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const HelpCenterScreen(),
                                ),
                              );
                            },
                          ),
                          ProfileMenuTile(
                            icon: Icons.privacy_tip_outlined,
                            title: 'Privacy Policy',
                            onTap: () => _openLegal(
                              'Privacy Policy',
                              kPrivacyPolicyBody,
                            ),
                          ),
                          ProfileMenuTile(
                            icon: Icons.description_outlined,
                            title: 'Terms of Service',
                            onTap: () => _openLegal(
                              'Terms of Service',
                              kTermsOfServiceBody,
                            ),
                          ),
                          ProfileMenuTile(
                            icon: Icons.info_outline_rounded,
                            title: 'About',
                            subtitle: 'App version and info',
                            onTap: _showAbout,
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'ACCOUNT & SECURITY',
                            style: TextStyle(
                              fontSize: 12,
                              letterSpacing: 1.4,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF8A9491),
                            ),
                          ),
                          const SizedBox(height: 10),
                          ProfileMenuTile(
                            icon: Icons.delete_outline_rounded,
                            title: 'Delete Account',
                            subtitle:
                                'Permanently delete your SocietyBites account and associated personal data.',
                            destructive: true,
                            onTap: _deletingAccount
                                ? () {}
                                : _confirmDeleteAccount,
                          ),
                          if (_deletingAccount) ...[
                            const SizedBox(height: 12),
                            const Row(
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFFD94F4F),
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Deleting your account...',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF6A7774),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 28),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: OutlinedButton.icon(
                              onPressed: _deletingAccount ? null : _logout,
                              icon: const Icon(Icons.logout_rounded, size: 20),
                              label: const Text(
                                'Log out',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFD94F4F),
                                side: const BorderSide(
                                  color: Color(0xFFE8B4B4),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _FulfilmentDraft {
  const _FulfilmentDraft({
    required this.mode,
    required this.inSocietyText,
    required this.nearbyText,
    required this.extendedText,
  });
  final FulfilmentMode mode;
  final String inSocietyText;
  final String nearbyText;
  final String extendedText;
}

class _FulfilmentSheet extends StatefulWidget {
  const _FulfilmentSheet({required this.initial});
  final SellerFulfilment initial;

  @override
  State<_FulfilmentSheet> createState() => _FulfilmentSheetState();
}

class _FulfilmentSheetState extends State<_FulfilmentSheet> {
  late FulfilmentMode _mode;
  late final TextEditingController _inSocietyController;
  late final TextEditingController _nearbyController;
  late final TextEditingController _extendedController;

  @override
  void initState() {
    super.initState();
    _mode = widget.initial.mode;
    _inSocietyController = TextEditingController(
      text: _chargeText(widget.initial.inSocietyCharge),
    );
    _nearbyController = TextEditingController(
      text: _chargeText(widget.initial.nearbyCharge),
    );
    _extendedController = TextEditingController(
      text: _chargeText(widget.initial.extendedCharge),
    );
  }

  String _chargeText(double amount) {
    return amount == amount.roundToDouble()
        ? amount.toInt().toString()
        : amount.toString();
  }

  @override
  void dispose() {
    _inSocietyController.dispose();
    _nearbyController.dispose();
    _extendedController.dispose();
    super.dispose();
  }

  Widget _chargeField({
    required String label,
    required String hint,
    required TextEditingController controller,
    Key? key,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF101617),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            key: key,
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              prefixText: '₹ ',
              hintText: hint,
              filled: true,
              fillColor: const Color(0xFFF5F7F6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE0E5E3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE0E5E3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF0E5A47)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final maxBodyHeight = (media.size.height * 0.68) - keyboard;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 28 + keyboard),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: maxBodyHeight.clamp(180.0, media.size.height),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Seller Fulfilment',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF101617),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'How will buyers receive their orders?',
                    style: TextStyle(fontSize: 14, color: Color(0xFF6A7774)),
                  ),
                  const SizedBox(height: 16),
                  ...FulfilmentMode.values.map((mode) {
                    final selected = mode == _mode;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Material(
                        color: const Color(0xFFF5F7F6),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => setState(() => _mode = mode),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Icon(
                                  selected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  color: const Color(0xFF0E5A47),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        mode.optionTitle,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF101617),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        mode.optionSubtitle,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF6A7774),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  if (_mode.showsDeliveryCharge) ...[
                    const SizedBox(height: 4),
                    const Text(
                      'Delivery charges',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF101617),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Set a charge for each buyer reach. In society defaults to ₹0.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF6A7774)),
                    ),
                    const SizedBox(height: 10),
                    _chargeField(
                      key: const Key('delivery-charge-in-society'),
                      label: 'In society',
                      hint: '0',
                      controller: _inSocietyController,
                    ),
                    _chargeField(
                      key: const Key('delivery-charge-nearby'),
                      label: 'Nearby',
                      hint: '0',
                      controller: _nearbyController,
                    ),
                    _chargeField(
                      key: const Key('delivery-charge-extended'),
                      label: 'Extended',
                      hint: '0',
                      controller: _extendedController,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              key: const Key('fulfilment-save'),
              onPressed: () => Navigator.pop(
                context,
                _FulfilmentDraft(
                  mode: _mode,
                  inSocietyText: _inSocietyController.text,
                  nearbyText: _nearbyController.text,
                  extendedText: _extendedController.text,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0E5A47),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Save',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentPreferenceSheet extends StatefulWidget {
  const _PaymentPreferenceSheet({required this.initial});
  final SellerPaymentPreference initial;

  @override
  State<_PaymentPreferenceSheet> createState() =>
      _PaymentPreferenceSheetState();
}

class _PaymentPreferenceSheetState extends State<_PaymentPreferenceSheet> {
  late SellerPaymentPreference _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PAYMENT METHODS',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101617),
            ),
          ),
          const SizedBox(height: 16),
          ...SellerPaymentPreference.values.map((option) {
            final selected = option == _value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: const Color(0xFFF5F7F6),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => setState(() => _value = option),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          selected
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          color: selected
                              ? const Color(0xFF0E5A47)
                              : const Color(0xFF8A9491),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                option.optionTitle,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF101617),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                option.optionSubtitle,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF6A7774),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, _value),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0E5A47),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Save',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.name,
    required this.phone,
    required this.role,
    required this.societyName,
    required this.flatNumber,
    required this.onEdit,
    this.photoUrl,
  });

  final String name;
  final String? phone;
  final String role;
  final String? societyName;
  final String? flatNumber;
  final String? photoUrl;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Row(
        children: [
          SellerAvatar(
            radius: 32,
            backgroundColor: const Color(0xFFE8F5EE),
            photoUrl: photoUrl,
            fallback: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0E5A47),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF101617),
                  ),
                ),
                const SizedBox(height: 4),
                if (phone != null)
                  Text(
                    phone!,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF6A7774),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _Chip(label: role),
                    if (flatNumber != null) _Chip(label: 'Flat $flatNumber'),
                    if (societyName != null) _Chip(label: societyName!),
                  ],
                ),
                if (societyName != null) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Society cannot be changed after joining',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8A9491),
                      fontWeight: FontWeight.w500,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            key: const Key('profile-edit-button'),
            tooltip: 'Edit profile',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_rounded),
            color: const Color(0xFF0E5A47),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5EE),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF0E5A47),
        ),
      ),
    );
  }
}

class _PendingSellerEnable {
  bool includeUpi = false;
  String? upiId;
  String? upiDisplayName;
  String? paymentPreference;
  String? sellingReachLevel;
  bool includeFulfilment = false;
  String? fulfilmentMode;
  double? deliveryCharge;
  double? deliveryChargeInSociety;
  double? deliveryChargeNearby;
  double? deliveryChargeExtended;
  bool includeFssai = false;
  String? fssaiNumber;
  String? fssaiRegisteredName;
  String? fssaiExpiry;

  Map<String, dynamic> toJson() {
    return {
      'termsVersion': sellerTermsVersion,
      if (includeUpi) 'upiId': upiId,
      if (includeUpi) 'upiDisplayName': upiDisplayName,
      if (paymentPreference != null) 'paymentPreference': paymentPreference,
      if (sellingReachLevel != null) 'sellingReachLevel': sellingReachLevel,
      if (includeFulfilment) 'fulfilmentMode': fulfilmentMode,
      if (includeFulfilment && deliveryCharge != null) 'deliveryCharge': deliveryCharge,
      if (includeFulfilment && deliveryChargeInSociety != null)
        'deliveryChargeInSociety': deliveryChargeInSociety,
      if (includeFulfilment && deliveryChargeNearby != null)
        'deliveryChargeNearby': deliveryChargeNearby,
      if (includeFulfilment && deliveryChargeExtended != null)
        'deliveryChargeExtended': deliveryChargeExtended,
      if (includeFssai)
        'fssai': {
          'number': fssaiNumber ?? '',
          if (fssaiRegisteredName != null) 'registeredName': fssaiRegisteredName,
          if (fssaiExpiry != null) 'expiry': fssaiExpiry,
        },
    };
  }
}

