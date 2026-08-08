import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/data.dart';
import '../services/api_service.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.order});

  final Order order;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  bool _isMarking = false;
  bool _isLoadingUpi = true;
  String? _sellerUpiId;
  String? _sellerUpiDisplayName;
  String? _loadError;

  bool get _hasUpi => _sellerUpiId != null && _sellerUpiId!.trim().isNotEmpty;

  bool get _isCashOrder =>
      (widget.order.paymentMethod ?? 'upi').toLowerCase() == 'cash';

  String get _sellerName {
    if (_sellerUpiDisplayName != null && _sellerUpiDisplayName!.isNotEmpty) {
      return _sellerUpiDisplayName!;
    }
    return widget.order.sellerLabel;
  }

  String get _amount => widget.order.orderTotal.toStringAsFixed(2);

  String get _upiQrData {
    final upiId = _sellerUpiId ?? '';
    return 'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(_sellerName)}'
        '&am=$_amount&tn=Order ${widget.order.orderId}';
  }

  String get _upiDeepLink {
    final upiId = _sellerUpiId ?? '';
    return 'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(_sellerName)}'
        '&am=$_amount&cu=INR&tn=SocietyBites Order ${widget.order.orderId}';
  }

  @override
  void initState() {
    super.initState();
    // Prefer UPI embedded on order items (set when listings were loaded).
    if (widget.order.items.isNotEmpty) {
      _sellerUpiId = widget.order.items.first.food.sellerUpiId;
    }
    _loadPaymentInfo();
  }

  Future<void> _loadPaymentInfo() async {
    setState(() {
      _isLoadingUpi = true;
      _loadError = null;
    });

    try {
      final data = await ApiService.getPaymentStatus(orderId: widget.order.id);
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

    final uri = Uri.parse(_upiDeepLink);
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No UPI app found. Please scan the QR code instead.'),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Could not open UPI app. Please scan the QR code instead.'),
        ),
      );
    }
  }

  Future<void> _markPaid() async {
    setState(() => _isMarking = true);
    try {
      await ApiService.markOrderPaid(orderId: widget.order.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to mark payment: $e')),
      );
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
          onPressed: () => Navigator.pop(context),
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
            if (_isLoadingUpi)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: CircularProgressIndicator(color: Color(0xFF0E5A47)),
              )
            else if (_hasUpi) ...[
              _buildQrSection(),
              const SizedBox(height: 24),
              _buildUpiButton(),
              const SizedBox(height: 16),
              _buildMarkPaidButton(
                label: "I've Paid via UPI",
              ),
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
                widget.order.orderId,
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
            'Scan to Pay',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101617),
            ),
          ),
          const SizedBox(height: 16),
          QrImageView(
            data: _upiQrData,
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
        label: const Text(
          'Pay via UPI App',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
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
              Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFB8860B), size: 22),
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
