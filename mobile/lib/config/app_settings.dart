import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const String _fontScaleKey = 'font_scale';

  double _fontScale = 1.0;
  double get fontScale => _fontScale;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _fontScale = prefs.getDouble(_fontScaleKey) ?? 1.0;
  }

  Future<void> setFontScale(double value) async {
    _fontScale = value;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontScaleKey, value);
  }

  String labelFor(double value) {
    if (value == 0.9) return '작게';
    if (value == 1.0) return '기본';
    if (value == 1.15) return '크게';
    if (value == 1.3) return '아주 크게';
    return '기본';
  }

  String get currentLabel => labelFor(_fontScale);
}
