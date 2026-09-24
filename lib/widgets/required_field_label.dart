import 'package:flutter/material.dart';

const requiredFieldAsteriskColor = Color(0xFFD94F4F);

const requiredFieldLabelStyle = TextStyle(
  fontSize: 11,
  letterSpacing: 1.2,
  fontWeight: FontWeight.w700,
  color: Color(0xFF6A7774),
);

class RequiredFieldLabel extends StatelessWidget {
  const RequiredFieldLabel(
    this.label, {
    super.key,
    this.required = false,
    this.style = requiredFieldLabelStyle,
  });

  final String label;
  final bool required;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: Text(label, style: style),
        ),
        if (required) ...[
          const SizedBox(width: 3),
          Semantics(
            label: 'required',
            child: Text(
              '*',
              style: style.copyWith(
                color: requiredFieldAsteriskColor,
                fontSize: (style.fontSize ?? 11) + 1,
                letterSpacing: 0,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class RequiredFieldsLegend extends StatelessWidget {
  const RequiredFieldsLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Required fields are marked with an asterisk',
      child: const Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '*',
              style: TextStyle(
                color: requiredFieldAsteriskColor,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
            TextSpan(
              text: ' Required fields',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF8A9491),
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
