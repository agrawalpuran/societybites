import 'package:flutter/material.dart';

import '../models/coupon.dart';
import '../services/api_service.dart';

class CheckoutCouponSection extends StatefulWidget {
  const CheckoutCouponSection({
    super.key,
    required this.orderSubtotal,
    required this.onQuoteChanged,
    this.validateCoupon,
  });

  final double orderSubtotal;
  final ValueChanged<CouponQuote?> onQuoteChanged;
  final Future<CouponQuote?> Function(String code, double orderSubtotal)?
      validateCoupon;

  @override
  State<CheckoutCouponSection> createState() => _CheckoutCouponSectionState();
}

class _CheckoutCouponSectionState extends State<CheckoutCouponSection> {
  final _controller = TextEditingController();
  CouponQuote? _applied;
  bool _loading = false;
  String? _error;

  @override
  void didUpdateWidget(CheckoutCouponSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderSubtotal != widget.orderSubtotal && _applied != null) {
      _clearApplied();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clearApplied() {
    setState(() {
      _applied = null;
      _error = null;
    });
    widget.onQuoteChanged(null);
  }

  Future<void> _apply() async {
    final code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter a coupon code');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final validate = widget.validateCoupon ?? ApiService.validateCoupon;
      final quote = await validate(code, widget.orderSubtotal);
      if (!mounted) return;
      if (quote == null) {
        setState(() {
          _applied = null;
          _error = 'This coupon could not be applied';
        });
        widget.onQuoteChanged(null);
        return;
      }
      setState(() {
        _applied = quote;
        _controller.text = quote.code;
      });
      widget.onQuoteChanged(quote);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _applied = null;
        _error = ApiService.userFacingError(error);
      });
      widget.onQuoteChanged(null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.confirmation_number_outlined,
                color: Color(0xFF3A4644), size: 22),
            SizedBox(width: 8),
            Text(
              'Coupon code',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF101617),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textCapitalization: TextCapitalization.characters,
                enabled: !_loading,
                decoration: InputDecoration(
                  hintText: 'e.g. WELCOME100',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onSubmitted: (_) => _apply(),
              ),
            ),
            const SizedBox(width: 8),
            if (_applied != null)
              IconButton(
                onPressed: _loading ? null : _clearApplied,
                tooltip: 'Remove coupon',
                icon: const Icon(Icons.close_rounded),
              )
            else
              FilledButton(
                onPressed: _loading ? null : _apply,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0E5A47),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Apply'),
              ),
          ],
        ),
        if (_applied != null) ...[
          const SizedBox(height: 8),
          Text(
            '${_applied!.code} applied · ${formatRupee(_applied!.discountAmount)} off food',
            style: const TextStyle(
              color: Color(0xFF0E5A47),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: const TextStyle(color: Color(0xFFB42318)),
          ),
        ],
      ],
    );
  }
}
