import 'package:flutter/material.dart';

/// Max width for admin main content on wide web (side nav stays full height).
const adminContentMaxWidth = 1200.0;

class AdminContentFrame extends StatelessWidget {
  const AdminContentFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: adminContentMaxWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: child,
        ),
      ),
    );
  }
}
