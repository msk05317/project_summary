import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  static const _kFontScale = 'settings.fontScale';
  static const _kNotif = 'settings.notificationsEnabled';
  static const _kUpdateNotif = 'settings.updateNotifEnabled';
  static const _kAutoRefresh = 'settings.autoRefreshMinutes';
  static const _kBgRefresh = 'settings.backgroundRefreshMinutes';

  final ValueNotifier<double> fontScale = ValueNotifier(1.0);
  final ValueNotifier<bool> notificationsEnabled = ValueNotifier(true);
  final ValueNotifier<bool> updateNotifEnabled = ValueNotifier(true);
  final ValueNotifier<int> autoRefreshMinutes = ValueNotifier(5); // 0=끔
  final ValueNotifier<int> backgroundRefreshMinutes = ValueNotifier(30); // 0=끔

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    fontScale.value = p.getDouble(_kFontScale) ?? 1.0;
    notificationsEnabled.value = p.getBool(_kNotif) ?? true;
    updateNotifEnabled.value = p.getBool(_kUpdateNotif) ?? true;
    autoRefreshMinutes.value = p.getInt(_kAutoRefresh) ?? 5;
    backgroundRefreshMinutes.value = p.getInt(_kBgRefresh) ?? 30;
  }

  Future<void> setFontScale(double v) async {
    fontScale.value = v;
    (await SharedPreferences.getInstance()).setDouble(_kFontScale, v);
  }

  Future<void> setNotificationsEnabled(bool v) async {
    notificationsEnabled.value = v;
    (await SharedPreferences.getInstance()).setBool(_kNotif, v);
  }

  Future<void> setUpdateNotifEnabled(bool v) async {
    updateNotifEnabled.value = v;
    (await SharedPreferences.getInstance()).setBool(_kUpdateNotif, v);
  }

  Future<void> setBackgroundRefreshMinutes(int v) async {
    backgroundRefreshMinutes.value = v;
    (await SharedPreferences.getInstance()).setInt(_kBgRefresh, v);
  }

  Future<void> setAutoRefreshMinutes(int v) async {
    autoRefreshMinutes.value = v;
    (await SharedPreferences.getInstance()).setInt(_kAutoRefresh, v);
  }
}
