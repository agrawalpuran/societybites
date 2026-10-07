import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../utils/picked_image.dart';

/// Address proof / document upload: camera, gallery, preview, replace, remove.
class DocumentImageUploadSection extends StatelessWidget {
  const DocumentImageUploadSection({
    super.key,
    required this.title,
    required this.subtitle,
    required this.bytes,
    required this.onPickFromSource,
    required this.onRemove,
    this.sheetTitle = 'Address proof',
    this.previewHeight = 170,
  });

  final String title;
  final String subtitle;
  final Uint8List? bytes;
  final Future<void> Function(ImageSource source) onPickFromSource;
  final VoidCallback onRemove;
  final String sheetTitle;
  final double previewHeight;

  @override
  Widget build(BuildContext context) {
    final hasImage = bytes != null && bytes!.isNotEmpty;
    final cacheWidth =
        (previewHeight * MediaQuery.devicePixelRatioOf(context)).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Color(0xFF101617),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 13,
            height: 1.4,
            color: Color(0xFF6A7774),
          ),
        ),
        const SizedBox(height: 12),
        if (!hasImage) ...[
          _PickRow(
            icon: Icons.photo_camera_outlined,
            label: 'Take Photo',
            onTap: () => onPickFromSource(ImageSource.camera),
          ),
          const SizedBox(height: 8),
          _PickRow(
            icon: Icons.photo_library_outlined,
            label: 'Choose from Gallery',
            onTap: () => onPickFromSource(ImageSource.gallery),
          ),
        ] else ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              height: previewHeight,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F2F1),
                border: Border.all(color: const Color(0xFFE0E5E3)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Image.memory(
                bytes!,
                width: double.infinity,
                height: previewHeight,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
                cacheWidth: cacheWidth > 0 ? cacheWidth : null,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('document-upload-replace'),
                  onPressed: () => onPickFromSource(ImageSource.gallery),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                  label: const Text('Replace'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0E5A47),
                    side: const BorderSide(color: Color(0xFF0E5A47)),
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('document-upload-remove'),
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  label: const Text('Remove'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6A7774),
                    side: const BorderSide(color: Color(0xFFE0E5E3)),
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF5F7F6),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: const Color(0xFF0E5A47), size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF3A4644),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the shared photo source sheet and returns picked bytes.
Future<PickedImage?> pickDocumentImage(
  BuildContext context, {
  String sheetTitle = 'Address proof',
}) {
  return pickImageViaSourceSheet(context, sheetTitle: sheetTitle);
}
