import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/models/order_lifecycle.dart';

Map<String, dynamic> loadOrderFixture(String name) {
  final file = File('test/fixtures/orders/$name.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  test('pending fixture parses and shows NEW', () {
    final order = Order.fromJson(loadOrderFixture('pending'));
    expect(order.id, 'ord-pending-1');
    expect(order.status, 'pending');
    expect(order.paymentStatus, 'pending');
    expect(SellerOrderLifecycle.forStatus(order.status).badge, 'NEW');
  });

  test('accepted fixture parses and shows ACCEPTED', () {
    final order = Order.fromJson(loadOrderFixture('accepted'));
    expect(order.status, 'accepted');
    expect(order.sellerCanDecline, isTrue);
    expect(SellerOrderLifecycle.forStatus(order.status).badge, 'ACCEPTED');
  });

  test('ready fixture parses and shows READY', () {
    final order = Order.fromJson(loadOrderFixture('ready'));
    expect(order.status, 'ready');
    expect(order.paymentStatus, 'paid');
    expect(SellerOrderLifecycle.forStatus(order.status).badge, 'READY');
  });

  test('completed fixture is COMPLETED on kitchen, not ACTIVE', () {
    final order = Order.fromJson(loadOrderFixture('completed'));
    expect(order.status, 'completed');
    expect(order.orderId, 'SE-051648');
    expect(order.paymentStatus, 'paid');
    expect(order.completedAt, isNotNull);
    expect(order.isTerminal, isTrue);
    expect(SellerOrderLifecycle.forStatus(order.status).badge, 'COMPLETED');
    expect(SellerOrderLifecycle.forStatus(order.status).hasPrimaryAction, isFalse);
    expect(order.isInBuyerActiveTab(DateTime.utc(2026, 10, 22, 17)), isTrue);
  });

  test('rejected fixture keeps reason for the buyer', () {
    final order = Order.fromJson(loadOrderFixture('rejected'));
    expect(order.status, 'rejected');
    expect(order.isRejected, isTrue);
    expect(order.rejectReason, 'Not enough time');
    expect(
      SellerOrderLifecycle.forStatus(order.status).badge,
      'ORDER REJECTED',
    );
  });

  test('fixtures share the contract keys both clients read', () {
    for (final name in ['pending', 'accepted', 'ready', 'completed', 'rejected']) {
      final json = loadOrderFixture(name);
      expect(json['id'], isNotEmpty, reason: '$name.id');
      expect(json['orderNumber'], isNotEmpty, reason: '$name.orderNumber');
      expect(json['status'], isNotEmpty, reason: '$name.status');
      expect(json['paymentStatus'], isNotEmpty, reason: '$name.paymentStatus');
      expect(json['items'], isA<List>(), reason: '$name.items');
    }
  });
}
