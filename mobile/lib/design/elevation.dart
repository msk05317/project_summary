// ============================================================
// File: lib/design/elevation.dart
// Section: Foundations / Elevation (Shadow)
// Figma:  Elevation tokens
// Note:   카드/모달의 그림자 강도를 토큰화
// ============================================================
import 'package:flutter/material.dart';

class AppElevation {
  AppElevation._();

  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x14000000), // ~8% black
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> modal = [
    BoxShadow(
      color: Color(0x29000000), // ~16% black
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];
}
