import 'package:flutter/material.dart';

/// Compact notice that sizes to its text. Long copy wraps; it does not
/// fill the remaining screen.
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    this.title,
    required this.message,
    this.action,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 8),
  });

  final String? title;
  final String message;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F7F4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD4E8DF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null && title!.trim().isNotEmpty) ...[
              Text(
                title!,
                softWrap: true,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101617),
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              message,
              softWrap: true,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Color(0xFF6A7774),
                fontWeight: FontWeight.w500,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 10),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
