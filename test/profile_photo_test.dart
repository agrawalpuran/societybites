import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/screens/profile_photo_crop_screen.dart';
import 'package:societybites/screens/profile_screen.dart';
import 'package:societybites/screens/seller_storefront_screen.dart';
import 'package:societybites/services/profile_photo_processor.dart';
import 'package:societybites/widgets/seller_avatar.dart';

void _ignoreOverflow() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = '${details.exception}\n${details.summary}';
    if (text.contains('A RenderFlex overflowed') ||
        text.contains('Incorrect use of ParentDataWidget') ||
        text.contains('HTTP request failed') ||
        text.contains('NetworkImage') ||
        text.contains('ImageCodecException')) {
      return;
    }
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

Uint8List _jpeg({int width = 80, int height = 80}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(14, 90, 71));
  return Uint8List.fromList(img.encodeJpg(image, quality: 80));
}

Map<String, dynamic> _sellerProfile({String? photo}) {
  return {
    'id': 'seller-1',
    'name': 'Anita',
    'role': 'seller',
    'profilePhotoUrl': photo,
    'sellingReachLevel': 'MY_SOCIETY',
    'sellingReach': {
      'cityKey': 'bengaluru',
      'nearbyRadiusKm': 5,
      'extendedRadiusKm': 10,
    },
    'fulfilmentMode': 'BUYER_PICKUP',
    'fssai': {'number': null},
    'society': {'name': 'Prestige Notting Hill'},
    'flat': {'flatNumber': '3062'},
  };
}

Future<void> _pumpProfile(
  WidgetTester tester, {
  Map<String, dynamic>? profile,
  Future<Uint8List?> Function(ImageSource source)? pick,
  Future<Uint8List?> Function(Uint8List bytes)? crop,
  Future<Map<String, dynamic>> Function(List<int> bytes)? upload,
  Future<Map<String, dynamic>> Function({String? profilePhotoUrl})? save,
}) async {
  SharedPreferences.setMockInitialValues({
    'user_id': 'seller-1',
    'user_role': 'seller',
    'user_name': 'Anita',
  });
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: ProfileScreen(
        fetchProfile: () async => profile ?? _sellerProfile(),
        pickProfilePhotoBytes: pick,
        cropProfilePhoto: crop,
        uploadProfilePhoto: upload,
        saveProfilePhoto: save,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.ensureVisible(find.text('Seller Settings'));
  await tester.tap(find.text('Seller Settings'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('encodeProfilePhoto resizes under 5 MB', () {
    final out = encodeProfilePhoto(_jpeg(width: 1600, height: 1200));
    expect(out.length, lessThan(profilePhotoMaxBytes));
    expect(looksLikeSupportedProfilePhoto(out), isTrue);
  });

  test('unsupported bytes are rejected', () {
    expect(
      () => encodeProfilePhoto(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])),
      throwsA(isA<ProfilePhotoRejected>()),
    );
  });

  test('listing JSON carries one seller photo used by Home sellers', () {
    final food = FoodItem.fromJson({
      'id': 'item-1',
      'name': 'Idli',
      'sellerId': 'seller-1',
      'sellerName': 'Anita',
      'price': 40,
      'sellerProfilePhotoUrl': 'https://cdn.example/anita.jpg',
    });
    expect(food.sellerProfilePhotoUrl, 'https://cdn.example/anita.jpg');
    final sellers = sellersFromListings([food]);
    expect(sellers.single.profilePhotoUrl, 'https://cdn.example/anita.jpg');
  });

  test('seller without photo keeps default hashed avatar', () {
    final food = FoodItem.fromJson({
      'id': 'item-1',
      'name': 'Idli',
      'sellerId': 'seller-1',
      'sellerName': 'Anita',
      'price': 40,
    });
    expect(food.sellerProfilePhotoUrl, isNull);
    final seller = sellerFromListing(food);
    expect(seller.profilePhotoUrl, isNull);
    expect(seller.avatarIcon, isNotNull);
  });

  testWidgets('gallery and camera both reach crop then upload', (tester) async {
    _ignoreOverflow();
    ImageSource? pickedSource;
    var cropped = false;
    var uploads = 0;
    await _pumpProfile(
      tester,
      pick: (source) async {
        pickedSource = source;
        return _jpeg();
      },
      crop: (bytes) async {
        cropped = true;
        return bytes;
      },
      upload: (bytes) async {
        uploads += 1;
        expect(bytes.length, lessThan(profilePhotoMaxBytes));
        return _sellerProfile(photo: 'https://cdn.example/anita.jpg');
      },
    );

    expect(find.text('Profile Photo'), findsOneWidget);
    expect(find.text('Change Photo'), findsOneWidget);
    expect(find.text('Remove'), findsNothing);

    await tester.ensureVisible(find.text('Change Photo'));
    await tester.tap(find.text('Change Photo'));
    await tester.pumpAndSettle();
    expect(find.text('Take Photo'), findsOneWidget);
    expect(find.text('Choose from Gallery'), findsOneWidget);
    await tester.tap(find.text('Choose from Gallery'));
    await tester.pumpAndSettle();
    expect(pickedSource, ImageSource.gallery);
    expect(cropped, isTrue);
    expect(uploads, 1);
    expect(find.text('Remove'), findsOneWidget);

    await tester.tap(find.text('Change Photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take Photo'));
    await tester.pumpAndSettle();
    expect(pickedSource, ImageSource.camera);
    expect(uploads, 2);
  });

  testWidgets('oversized processed photo shows a clear error', (tester) async {
    _ignoreOverflow();
    await _pumpProfile(
      tester,
      profile: _sellerProfile(),
      pick: (_) async => _jpeg(),
      crop: (_) async {
        throw const ProfilePhotoRejected(profilePhotoTooLargeMessage);
      },
    );
    await tester.ensureVisible(find.text('Change Photo'));
    await tester.tap(find.text('Change Photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take Photo'));
    await tester.pumpAndSettle();
    expect(find.text(profilePhotoTooLargeMessage), findsOneWidget);
  });

  testWidgets('seller can remove a profile photo', (tester) async {
    _ignoreOverflow();
    await _pumpProfile(
      tester,
      profile: _sellerProfile(photo: 'https://cdn.example/anita.jpg'),
      save: ({profilePhotoUrl}) async => _sellerProfile(),
    );
    expect(find.text('Remove'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove'), findsNothing);
  });

  testWidgets('crop screen shows circular adjust and Use Photo', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ProfilePhotoCropScreen(imageBytes: _jpeg())),
    );
    expect(find.text('Adjust photo'), findsOneWidget);
    expect(find.text('Use Photo'), findsOneWidget);
    expect(find.byType(ClipOval), findsWidgets);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('storefront uses the listing seller photo', (tester) async {
    _ignoreOverflow();
    await tester.pumpWidget(
      MaterialApp(
        home: SellerStorefrontScreen(
          seller: sellerFromListing(
            FoodItem.fromJson({
              'id': 'item-1',
              'name': 'Idli',
              'sellerId': 'seller-1',
              'sellerName': 'Anita',
              'price': 40,
              'sellerProfilePhotoUrl': 'https://cdn.example/anita.jpg',
            }),
          ),
          fetchListings: () async => [
            {
              'id': 'item-1',
              'name': 'Idli',
              'sellerId': 'seller-1',
              'sellerName': 'Anita',
              'price': 40,
              'status': 'active',
              'sellerProfilePhotoUrl': 'https://cdn.example/anita.jpg',
            },
          ],
          fetchCampaigns: () async => const [],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final avatar = tester.widget<SellerAvatar>(find.byType(SellerAvatar).first);
    expect(avatar.photoUrl, 'https://cdn.example/anita.jpg');
  });

  testWidgets('buyer profile does not show seller photo editor', (tester) async {
    _ignoreOverflow();
    SharedPreferences.setMockInitialValues({
      'user_id': 'buyer-1',
      'user_role': 'buyer',
      'user_name': 'Ravi',
    });
    await tester.binding.setSurfaceSize(const Size(800, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          fetchProfile: () async => {
            'id': 'buyer-1',
            'name': 'Ravi',
            'role': 'buyer',
            'society': {'name': 'Prestige Notting Hill'},
            'flat': {'flatNumber': '1'},
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Profile Photo'), findsNothing);
    expect(find.text('FSSAI details'), findsNothing);
    expect(find.text('Seller Settings'), findsNothing);
  });
}
