import 'package:flutter/material.dart';

import '../models/seller_terms.dart';

class SellerTermsScreen extends StatefulWidget {
  const SellerTermsScreen({super.key});

  @override
  State<SellerTermsScreen> createState() => _SellerTermsScreenState();
}

class _SellerTermsScreenState extends State<SellerTermsScreen> {
  bool _agreed = false;

  void _decline() {
    Navigator.pop(context, false);
  }

  void _accept() {
    if (!_agreed) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Seller Terms & Conditions',
          style: TextStyle(
            color: Color(0xFF101617),
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        leading: IconButton(
          key: const Key('seller-terms-back'),
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Color(0xFF3A4644)),
          onPressed: _decline,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sellerTermsIntro,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF223531),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    sellerTermsBody.trim(),
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: Color(0xFF3A4644),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Material(
            color: Colors.white,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CheckboxListTile(
                      key: const Key('seller-terms-agree'),
                      value: _agreed,
                      onChanged: (value) {
                        setState(() => _agreed = value == true);
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      activeColor: const Color(0xFF0E5A47),
                      title: const Text(
                        'I have read and agree to the SocietyEats Seller Terms & Conditions.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF223531),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        key: const Key('seller-terms-accept'),
                        onPressed: _agreed ? _accept : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0E5A47),
                          disabledBackgroundColor: const Color(0xFFD5DDDA),
                          foregroundColor: Colors.white,
                          disabledForegroundColor: const Color(0xFF8A9491),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Accept & Continue',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    TextButton(
                      key: const Key('seller-terms-decline'),
                      onPressed: _decline,
                      child: const Text(
                        'Back',
                        style: TextStyle(
                          color: Color(0xFF3A4644),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
