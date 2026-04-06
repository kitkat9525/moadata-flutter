import 'package:flutter/material.dart';

const double kScreenTopPadding = 50.0;
const EdgeInsets kScreenPadding = EdgeInsets.fromLTRB(16.0, kScreenTopPadding, 16.0, 16.0);
const Color kAccentColor = Color(0xFF00A9CE);
const Color kScreenBackgroundColor = Color(0xFFF8F9FA);

BoxDecoration buildCardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Colors.grey.shade200),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.02),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

TextStyle buildSectionTitleStyle() {
  return TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.bold,
    color: Colors.grey.shade500,
  );
}
