import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/data.dart';
import '../services/api_service.dart';
import '../services/upi_payment_service.dart';

typedef PaymentApiCall = Future<Map<String, dynamic>> Function(String orderId);
typedef UpiLauncher = Future<bool> Function(Uri uri);

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({
    super.key,
    required this.order,
    this.fetchOrder,
    this.fetchPaymentInfo,
    this.markPaid,
    this.launchUpi,
    this.pollInterval = const Duration(seconds: 8),
  });

  final Order order;
  final PaymentApiCall? fetchOrder;
  final PaymentApiCall? fetchPaymentInfo;
  final PaymentApiCall? markPaid;
  final UpiLauncher? launchUpi;
  final Duration pollInterval;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen>
    with WidgetsBindingObserver {
  late Order _order;
  Timer? _pollTimer;
  bool _isMarking = false;
  bool _isLoadingUpi = true;
  bool _isRefreshingOrder = false;
  bool _isLeavingForProgress = false;
  String? _sellerUpiId;
  String? _sellerUpiDisplayName;
  String? _loadError;
  String? _upiLaunchError;

  bool get _hasUpi => _sellerUpiId != null && isValidUpiId(_sellerUpiId!);

  bool get _isCashOrder =>
      (_order.paymentMethod ?? 'upi').toLowerCase() == 'cash';

  bool get _isAwaitingSeller =>
      _order.paymentStatus == 'buyer_marked_paid' &&
      _order.status == 'accepted';

  bool get _showUpiIntentButton =>
      shouldOfferUpiIntent(isWeb: kIsWeb, platform: defaultTargetPlatform);

  String get _sellerName {
    if (_sellerUpiDisplayName != null && _sellerUpiDisplayName!.isNotEmpty) {
      return _sellerUpiDisplayName!;
    }
    return _order.sellerLabel;
  }

  String get _amount => _order.orderTotal.toStringAsFixed(2);
  String get _displayAmount =>
      _order.orderTotal == _order.orderTotal.roundToDouble()
      ? _order.orderTotal.toStringAsFixed(0)
      : _amount;

  Uri get _upiPaymentUri => buildUpiPaymentUri(
    upiId: _sellerUpiId ?? '',
    payeeName: _sellerName,
    amount: _order.orderTotal,
    transactionNote: 'SocietyBites Order #${_order.orderId}',
  );

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    WidgetsBinding.instance.addObserver(this);
    // Prefer UPI embedded on order items (set when listings were loaded).
    if (_order.items.isNotEmpty) {
      _sellerUpiId = _order.items.first.food.sellerUpiId;
    }
    _loadPaymentInfo();
    _refreshOrder();
    _pollTimer = Timer.periodic(widget.pollInterval, (_) => _refreshOrder());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshOrder();
    }
  }

  Future<Map<String, dynamic>> _fetchOrder(String orderId) {
    final fetch = widget.fetchOrder;
    return fetch != null ? fetch(orderId) : ApiService.getOrderById(orderId);
  }

  Future<Map<String, dynamic>> _fetchPaymentInfo(String orderId) {
    final fetch = widget.fetchPaymentInfo;
    return fetch != null
        ? fetch(orderId)
        : ApiService.getPaymentStatus(orderId: orderId);
  }

  Future<Map<String, dynamic>> _markOrderPaid(String orderId) {
    final mark = widget.markPaid;
    return mark != null
        ? mark(orderId)
        : ApiService.markOrderPaid(orderId: orderId);
  }

  Future<void> _refreshOrder() async {
    if (_isRefreshingOrder || _isLeavingForProgress) return;
    _isRefreshingOrder = true;
    try {
      final data = await _fetchOrder(_order.id);
      if (!mounted) return;

      final latest = Order.fromJson(data);
      setState(() {
        _order = latest;
        if (latest.items.isNotEmpty) {
          final latestUpi = latest.items.first.food.sellerUpiId;
          if (latestUpi != null && latestUpi.trim().isNotEmpty) {
            _sellerUpiId = latestUpi.trim();
          }
        }
      });

      if (latest.status != 'accepted' ||
          latest.paymentStatus == 'seller_confirmed' ||
          latest.paymentStatus == 'paid' ||
          latest.paymentStatus == 'failed') {
        _isLeavingForProgress = true;
        if (mounted) Navigator.pop(context, true);
      }
    } catch (_) {
      // Keep the last server snapshot and retry on the next poll/resume.
    } finally {
      _isRefreshingOrder = false;
    }
  }

  Future<void> _loadPaymentInfo() async {
    setState(() {
      _isLoadingUpi = true;
      _loadError = null;
    });

    try {
      final data = await _fetchPaymentInfo(_order.id);
      if (!mounted) return;

      final apiUpi = data['sellerUpiId'] as String?;
      setState(() {
        if (apiUpi != null && apiUpi.trim().isNotEmpty) {
          _sellerUpiId = apiUpi.trim();
        }
        _sellerUpiDisplayName = data['sellerUpiDisplayName'] as String?;
        _isLoadingUpi = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingUpi = false;
        // Keep any UPI already known from the order; only surface error if none.
        if (!_hasUpi) {
          _loadError = e.toString();
        }
      });
    }
  }

  Future<void> _launchUpiApp() async {
    if (!_hasUpi) return;

    try {
      setState(() => _upiLaunchError = null);
      final uri = _upiPaymentUri;
      final launch = widget.launchUpi;
      final launched = launch != null
          ? await launch(uri)
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        setState(() {
          _upiLaunchError =
              "We couldn't open a UPI app. Please use the QR code below to complete payment.";
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _upiLaunchError =
            "We couldn't open a UPI app. Please use the QR code below to complete payment.";
      });
    }
  }

  Future<void> _markPaid() async {
    setState(() => _isMarking = true);
    try {
      final data = await _markOrderPaid(_order.id);
      if (!mounted) return;
      setState(() => _order = Order.fromJson(data));
      await _refreshOrder();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to mark payment: $e')));
    } finally {
      if (mounted) setState(() => _isMarking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAF9),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF101617)),
          onPressed: () => Navigator.pop(context, true),
        ),
        title: const Text(
          'Payment',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF101617),
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          children: [
            _buildOrderSummary(),
            const SizedBox(height: 28),
            if (_isAwaitingSeller)
              _buildAwaitingSeller()
            else if (_isLoadingUpi)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: CircularProgressIndicator(color: Color(0xFF0E5A47)),
              )
            else if (_hasUpi) ...[
              if (_showUpiIntentButton) ...[
                _buildUpiButton(),
                if (_upiLaunchError != null) ...[
                  const SizedBox(height: 12),
                  _buildUpiLaunchError(),
                ],
                const SizedBox(height: 20),
                _buildOrDivider(),
                const SizedBox(height: 20),
              ],
              _buildQrSection(),
              const SizedBox(height: 16),
              _buildMarkPaidButton(label: "I've Paid via UPI"),
            ] else ...[
              _buildNoUpiMessage(),
              if (_loadError != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Could not refresh seller UPI: $_loadError',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFD94F4F),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              // Cash / offline fallback — still let buyer notify seller.
              _buildMarkPaidButton(
                label: _isCashOrder
                    ? "I've arranged cash payment"
                    : "I've paid / will pay at pickup",
              ),
            ],
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderSummary() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Order',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6A7774),
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _order.orderId,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF101617),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Pay to',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6A7774),
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _sellerName,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF101617),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const Divider(height: 28, color: Color(0xFFEAEFED)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Amount',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF101617),
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '₹$_amount',
                style: const TextStyle(
                  fontSize: 22,
                  color: Color(0xFF0E5A47),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAwaitingSeller() {
    return Container(
      key: const ValueKey('awaiting-seller-confirmation'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8DFC0)),
      ),
      child: const Column(
        children: [
          Icon(Icons.hourglass_top_rounded, color: Color(0xFFB8860B), size: 30),
          SizedBox(height: 10),
          Text(
            'Awaiting seller confirmation',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF7A5A20),
            ),
          ),
          SizedBox(height: 6),
          Text(
            'We’ll refresh this order automatically. Once the seller confirms payment, you’ll return to order progress.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF7A5A20),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Column(
        children: [
          const Text(
            'Scan QR code',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101617),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'If you’re using another phone to pay, scan this code with your UPI app.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF6A7774),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          QrImageView(
            data: _upiPaymentUri.toString(),
            version: QrVersions.auto,
            size: 200,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Color(0xFF0E5A47),
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Color(0xFF101617),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'UPI ID: ${_sellerUpiId ?? ''}',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6A7774),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpiButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _launchUpiApp,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0E5A47),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        icon: const Icon(Icons.open_in_new_rounded, size: 20),
        label: Text(
          'Pay ₹$_displayAmount via UPI',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
    );
  }

  Widget _buildOrDivider() {
    return const Row(
      children: [
        Expanded(child: Divider(color: Color(0xFFE0E5E3))),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or',
            style: TextStyle(
              color: Color(0xFF8A9491),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: Divider(color: Color(0xFFE0E5E3))),
      ],
    );
  }

  Widget _buildUpiLaunchError() {
    return Container(
      key: const ValueKey('upi-launch-error'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD4D4)),
      ),
      child: Text(
        _upiLaunchError!,
        style: const TextStyle(
          color: Color(0xFFD94F4F),
          fontSize: 13,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _buildNoUpiMessage() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8DFC0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFB8860B),
                size: 22,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'UPI not available yet',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF7A5A20),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _isCashOrder
                ? 'This order is set to cash. Pay the seller at pickup, then tap below so they can confirm.'
                : 'This seller has not added a UPI ID, so QR / UPI pay cannot be shown. '
                      'Contact them or pay at pickup, then tap below after you have paid.',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF7A5A20),
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarkPaidButton({required String label}) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: _isMarking ? null : _markPaid,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFF0E5A47), width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: _isMarking
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF0E5A47),
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Color(0xFF0E5A47),
                ),
              ),
      ),
    );
  }
}
