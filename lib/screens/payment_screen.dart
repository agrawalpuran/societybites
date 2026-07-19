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

  String? get _sellerUpiId {
    if (widget.order.items.isEmpty) return null;
    return widget.order.items.first.food.sellerUpiId;
  }

  String get _sellerName => widget.order.sellerLabel;

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

  Future<void> _launchUpiApp() async {
    final uri = Uri.parse(_upiDeepLink);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
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
          content: Text('Could not open UPI app. Please scan the QR code instead.'),
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
            if (_sellerUpiId != null && _sellerUpiId!.isNotEmpty) ...[
              _buildQrSection(),
              const SizedBox(height: 24),
              _buildUpiButton(),
              const SizedBox(height: 16),
            ] else
              _buildNoUpiMessage(),
            const SizedBox(height: 12),
            _buildMarkPaidButton(),
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
                'Seller',
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
          const SizedBox(height: 14),
          const Divider(color: Color(0xFFEAEFED)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Amount',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF101617),
                ),
              ),
              Text(
                '₹${widget.order.orderTotal.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0E5A47),
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
      child: const Text(
        'Seller has not set up UPI payment yet. '
        'Please pay in cash upon pickup and mark as paid below.',
        style: TextStyle(
          fontSize: 13,
          color: Color(0xFF7A5A20),
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildMarkPaidButton() {
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
            : const Text(
                "I've Paid",
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Color(0xFF0E5A47),
                ),
              ),
      ),
    );
  }
}
