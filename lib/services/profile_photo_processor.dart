import 'dart:typed_data';

import 'package:image/image.dart' as img;

const int profilePhotoMaxBytes = 5 * 1024 * 1024;
const int profilePhotoMaxEdge = 512;
const String profilePhotoTooLargeMessage =
    'Photo is too large. Please choose another photo.';
const String profilePhotoUnsupportedMessage =
    'Unsupported photo type. Use JPG, PNG, or WebP.';

final class ProfilePhotoRejected implements Exception {
  const ProfilePhotoRejected(this.message);
  final String message;

  @override
  String toString() => message;
}

bool looksLikeSupportedProfilePhoto(List<int> bytes) {
  if (bytes.length < 12) return false;
  if (bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff) return true;
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47) {
    return true;
  }
  final riff = String.fromCharCodes(bytes.take(4));
  final webp = String.fromCharCodes(bytes.skip(8).take(4));
  return riff == 'RIFF' && webp == 'WEBP';
}

Uint8List encodeProfilePhoto(Uint8List input) {
  if (!looksLikeSupportedProfilePhoto(input)) {
    throw const ProfilePhotoRejected(profilePhotoUnsupportedMessage);
  }
  final decoded = img.decodeImage(input);
  if (decoded == null) {
    throw const ProfilePhotoRejected(profilePhotoUnsupportedMessage);
  }
  var square = decoded;
  final edge = square.width < square.height ? square.width : square.height;
  if (square.width != square.height) {
    square = img.copyCrop(
      square,
      x: ((square.width - edge) / 2).round(),
      y: ((square.height - edge) / 2).round(),
      width: edge,
      height: edge,
    );
  }
  if (square.width > profilePhotoMaxEdge) {
    square = img.copyResize(
      square,
      width: profilePhotoMaxEdge,
      height: profilePhotoMaxEdge,
      interpolation: img.Interpolation.linear,
    );
  }
  var quality = 85;
  var out = Uint8List.fromList(img.encodeJpg(square, quality: quality));
  while (out.length > profilePhotoMaxBytes && quality > 40) {
    quality -= 10;
    out = Uint8List.fromList(img.encodeJpg(square, quality: quality));
  }
  if (out.length > profilePhotoMaxBytes) {
    throw const ProfilePhotoRejected(profilePhotoTooLargeMessage);
  }
  return out;
}
