import 'package:flutter/material.dart';

import 'seller_avatar.dart';

class ProfileMenuTile extends StatelessWidget {
  const ProfileMenuTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailingLabel,
    this.destructive = false,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailingLabel;
  final bool destructive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent =
        destructive ? const Color(0xFFD94F4F) : const Color(0xFF0E5A47);
    final iconBg =
        destructive ? const Color(0xFFFBEAEA) : const Color(0xFFF0F2F1);
    final border =
        destructive ? const Color(0xFFE8B4B4) : const Color(0xFFEAEFED);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          onTap: onTap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: destructive
                  ? const Color(0xFFD94F4F)
                  : const Color(0xFF101617),
            ),
          ),
          subtitle: subtitle != null
              ? Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6A7774),
                  ),
                )
              : null,
          trailing: trailingLabel == null
              ? Icon(
                  Icons.chevron_right_rounded,
                  color: destructive
                      ? const Color(0xFFE8B4B4)
                      : const Color(0xFFADB5B2),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      trailingLabel!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFFADB5B2),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class ProfilePhotoSection extends StatelessWidget {
  const ProfilePhotoSection({
    super.key,
    required this.photoUrl,
    required this.name,
    required this.saving,
    required this.onChangePhoto,
    this.onRemovePhoto,
  });

  final String? photoUrl;
  final String name;
  final bool saving;
  final VoidCallback onChangePhoto;
  final VoidCallback? onRemovePhoto;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Profile Photo',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF3A4644),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SellerAvatar(
            radius: 36,
            backgroundColor: const Color(0xFFE8F5EE),
            photoUrl: photoUrl,
            fallback: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0E5A47),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (saving)
            const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: onChangePhoto,
                  child: const Text('Change Photo'),
                ),
                if (onRemovePhoto != null) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: onRemovePhoto,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFD94F4F),
                    ),
                    child: const Text('Remove'),
                  ),
                ],
              ],
            ),
          const SizedBox(height: 4),
          const Text(
            'Add a photo so buyers can recognize your kitchen more easily.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF8A9491),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
