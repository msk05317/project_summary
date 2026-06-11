import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const String _fontScaleKey = 'font_scale';
  static const String _lastDivisionKeyKey = 'last_division_key';
  static String _lastSeenKeyFor(String divisionId) => 'last_seen_$divisionId';

  double _fontScale = 1.0;
  double get fontScale => _fontScale;

  String? _lastDivisionKey;
  String? get lastDivisionKey => _lastDivisionKey;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _fontScale = prefs.getDouble(_fontScaleKey) ?? 1.0;
    _lastDivisionKey = prefs.getString(_lastDivisionKeyKey);
  }

  Future<void> setFontScale(double value) async {
    _fontScale = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontScaleKey, value);
  }

  Future<void> setLastDivisionKey(String? key) async {
    _lastDivisionKey = key;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (key == null) {
      await prefs.remove(_lastDivisionKeyKey);
    } else {
      await prefs.setString(_lastDivisionKeyKey, key);
    }
  }

  String labelFor(double value) {
    if (value == 0.9) return '작게';
    if (value == 1.0) return '기본';
    if (value == 1.15) return '크게';
    if (value == 1.3) return '아주 크게';
    return '기본';
  }

  Future<String?> getLastSeenAt(String divisionId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastSeenKeyFor(divisionId));
  }

  Future<void> markDivisionSeen(String divisionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _lastSeenKeyFor(divisionId),
      DateTime.now().toIso8601String(),
    );
    notifyListeners();
  }

  String get currentLabel => labelFor(_fontScale);
}
