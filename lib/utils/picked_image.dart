import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../widgets/photo_source_sheet.dart';

/// Lightweight image picked from camera or gallery (bytes kept in memory only).
class PickedImage {
  const PickedImage({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;
}

const double kDocumentPickMaxWidth = 1600;
const int kDocumentPickQuality = 85;

/// Reuses the app-wide photo source sheet and picker limits used for listings.
Future<PickedImage?> pickImageViaSourceSheet(
  BuildContext context, {
  required String sheetTitle,
  ImagePicker? picker,
}) async {
  final source = await showPhotoSourceSheet(context, title: sheetTitle);
  if (source == null || !context.mounted) return null;

  final imagePicker = picker ?? ImagePicker();
  try {
    final file = await imagePicker.pickImage(
      source: source,
      maxWidth: kDocumentPickMaxWidth,
      imageQuality: kDocumentPickQuality,
    );
    if (file == null || !context.mounted) return null;
    final bytes = await file.readAsBytes();
    if (!context.mounted) return null;
    return PickedImage(
      bytes: bytes,
      mimeType: file.mimeType ?? 'image/jpeg',
    );
  } on PlatformException catch (error) {
    if (!context.mounted) return null;
    final denied = error.code.toLowerCase().contains('denied') ||
        (error.message?.toLowerCase().contains('denied') ?? false) ||
        (error.message?.toLowerCase().contains('permission') ?? false);
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
    return null;
  }
}
