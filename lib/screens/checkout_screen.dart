import 'package:flutter/material.dart';
import 'main_shell_screen.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_header.dart';
import '../widgets/listing_image.dart';
import '../models/data.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.cartItems});

  final List<CartItem> cartItems;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

enum PaymentMethod { upi, cash }

class _CheckoutScreenState extends State<CheckoutScreen> {
  late List<CartItem> _items;
  PaymentMethod _payment = PaymentMethod.upi;
  double _platformFee = 0;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _items = List<CartItem>.from(widget.cartItems);
    _loadPlatformFee();
  }

  Future<void> _loadPlatformFee() async {
    try {
      final fee = await ApiService.getPlatformFee();
      if (!mounted) return;
      setState(() => _platformFee = fee);
    } catch (_) {
      // Keep default 0 if settings unavailable.
    }
  }

  double get _subtotal =>
      _items.fold<double>(0, (sum, item) => sum + item.total);

  double get _grandTotal => _subtotal + _platformFee;

  int get _totalQuantity =>
      _items.fold<int>(0, (sum, item) => sum + item.quantity);

  bool get _canConfirm =>
      !_isSubmitting && _items.isNotEmpty && _totalQuantity > 0;

  void _goToShell(int index) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => MainShellScreen(initialIndex: index),
      ),
      (_) => false,
    );
  }

  void _updateQuantity(int index, int delta) {
    final maxAvailable = _items[index].food.quantity;
    final proposed = _items[index].quantity + delta;
    if (delta > 0 && proposed > maxAvailable) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            maxAvailable <= 0
                ? '${_items[index].food.name} is sold out'
                : 'Only $maxAvailable portions available for ${_items[index].food.name}',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFD94F4F),
        ),
      );
      return;
    }

    var becameEmpty = false;
    setState(() {
      final next = List<CartItem>.from(_items);
      next[index].quantity = proposed;
      if (next[index].quantity <= 0) {
        next.removeAt(index);
      }
      _items = next.where((item) => item.quantity > 0).toList();
      becameEmpty = _items.isEmpty;
    });

    // Never leave the user on an empty checkout screen without shell nav.
    if (becameEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your cart is empty')),
        );
        _goToShell(0);
      });
    }
  }

  Future<void> _confirmOrder() async {
    if (!_canConfirm) return;

    setState(() => _isSubmitting = true);

    try {
      final societyId = await SessionService.getSocietyId();
      if (societyId == null || societyId.isEmpty) {
        throw Exception('Join your society before placing an order.');
      }

      await ApiService.createOrder(
        societyId: societyId,
        paymentMethod:
            _payment == PaymentMethod.upi ? 'upi' : 'cash',
        items: _items
            .map((item) => {
                  'listingId': item.food.id,
                  'quantity': item.quantity,
                })
            .toList(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Order confirmed! Your food is being prepared.'),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: const Color(0xFF0E5A47),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      var message = e.toString();
      if (message.startsWith('Exception: ')) {
        message = message.substring('Exception: '.length);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _items.isEmpty
                  ? const Center(
                      child: Text(
                        'Returning to Home…',
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF8A9491),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildProgressBar(),
                          const SizedBox(height: 18),
                          const _StepBadge(),
                          const SizedBox(height: 14),
                          const Text(
                            'Review your\ncommunity order',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF101617),
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 24),
                          ..._items
                              .asMap()
                              .entries
                              .map((e) => _OrderItemCard(
                                    item: e.value,
                                    onIncrement: () =>
                                        _updateQuantity(e.key, 1),
                                    onDecrement: () =>
                                        _updateQuantity(e.key, -1),
                                  )),
                          const SizedBox(height: 24),
                          _buildPaymentSection(),
                          const SizedBox(height: 24),
                          _buildBillSummary(size),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        selectedIndex: 0,
        onTap: _goToShell,
      ),
    );
  }

  Widget _buildHeader() {
    return const AppHeader();
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFF0E5A47),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFF0E5A47),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFD4DBD8),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.payment_rounded, color: Color(0xFF3A4644), size: 22),
            SizedBox(width: 8),
            Text(
              'Payment Method',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF101617),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _PaymentOption(
          icon: Icons.account_balance_wallet_rounded,
          iconColor: const Color(0xFF0E5A47),
          title: 'UPI Payment',
          subtitle: "Instant transfer to seller's wallet",
          isSelected: _payment == PaymentMethod.upi,
          onTap: () => setState(() => _payment = PaymentMethod.upi),
        ),
        const SizedBox(height: 10),
        _PaymentOption(
          icon: Icons.money_rounded,
          iconColor: const Color(0xFF8A9491),
          title: 'Cash on Pickup',
          subtitle: 'Pay when you collect your food',
          isSelected: _payment == PaymentMethod.cash,
          onTap: () => setState(() => _payment = PaymentMethod.cash),
        ),
      ],
    );
  }

  Widget _buildBillSummary(Size size) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF5EE), Color(0xFFFEECE0)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          _BillRow(
              label: 'Subtotal ($_totalQuantity items)',
              value: '₹${_subtotal.toStringAsFixed(0)}'),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                'Platform Fee',
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFF5A4A3A),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '₹${_platformFee.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF3A2A1A),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TOTAL AMOUNT',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      color: Color(0xFF8A7A6A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '₹${_grandTotal.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2A1A0A),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _canConfirm ? _confirmOrder : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0E5A47),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFB5C4BF),
                    disabledForegroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Confirm\nOrder',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE5D6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'CHECKOUT JOURNEY',
        style: TextStyle(
          color: Color(0xFF4E2A20),
          fontSize: 11,
          letterSpacing: 1.3,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _OrderItemCard extends StatelessWidget {
  const _OrderItemCard({
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
  });

  final CartItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            height: 140,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
            ),
            child: ListingImage(
              food: item.food,
              height: 140,
              borderRadius: 18,
              iconSize: 64,
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              item.food.name,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF101617),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Freshly made by ${item.food.sellerName} · ${item.food.locationLabel}',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF6A7774),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _QuantityButton(
                icon: Icons.remove,
                onTap: onDecrement,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '${item.quantity}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF101617),
                  ),
                ),
              ),
              _QuantityButton(
                icon: Icons.add,
                onTap: onIncrement,
                filled: true,
              ),
              const SizedBox(width: 14),
              Text(
                '₹${item.total.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101617),
                ),
              ),
              const Spacer(),
              Text(
                item.food.quantity <= 0
                    ? 'Sold out'
                    : '${item.food.quantity} left',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: item.food.quantity <= 0
                      ? const Color(0xFFD94F4F)
                      : const Color(0xFF6A7774),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuantityButton extends StatelessWidget {
  const _QuantityButton({
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: filled ? const Color(0xFF0E5A47) : Colors.white,
          shape: BoxShape.circle,
          border: filled
              ? null
              : Border.all(color: const Color(0xFFD4DBD8), width: 1.5),
        ),
        child: Icon(
          icon,
          size: 20,
          color: filled ? Colors.white : const Color(0xFF3A4644),
        ),
      ),
    );
  }
}

class _PaymentOption extends StatelessWidget {
  const _PaymentOption({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF0F7F4) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF0E5A47)
                : const Color(0xFFEAEFED),
            width: isSelected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFFE0F0EA)
                    : const Color(0xFFF5F7F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF101617),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF8A9491),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF0E5A47)
                      : const Color(0xFFD4DBD8),
                  width: isSelected ? 6 : 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            color: Color(0xFF5A4A3A),
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            color: Color(0xFF3A2A1A),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
