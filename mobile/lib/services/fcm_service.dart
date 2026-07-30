import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io' show Platform;

class FcmService {
  static const String _apiBase = 'https://project-summary-mkoo.fly.dev';
  static bool _initialized = false;

  static final FlutterLocalNotificationsPlugin _localNotifs =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'briefing_alarm',
    '사업부 진행현황 알림',
    description: '카드 상태 변경 및 중요 이슈 알림',
    importance: Importance.high,
  );

  /// 앱 시작 시 1회 호출.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await Firebase.initializeApp();
      debugPrint('[FCM] Firebase initialized');
    } catch (e) {
      debugPrint('[FCM] Firebase init failed: $e');
      return;
    }

    // 로컬 알림 초기화 (Android)
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await _localNotifs.initialize(settings: initSettings);
      await _localNotifs
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
      debugPrint('[FCM] local notifications initialized');
    } catch (e) {
      debugPrint('[FCM] local notif init failed: $e');
    }

    // 알림 권한 요청
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('[FCM] permission: ${settings.authorizationStatus}');
    } catch (e) {
      debugPrint('[FCM] permission request failed: $e');
    }

    // 토큰 획득
    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken();
      debugPrint('[FCM] token: ${token?.substring(0, 20)}...');
    } catch (e) {
      debugPrint('[FCM] getToken failed: $e');
      return;
    }

    if (token == null) return;

    // 릴리즈/디버그 모두 서버에 등록. debug 라벨은 로깅 참고용.
    final isDebug = kDebugMode;
    try {
      final res = await http.post(
        Uri.parse('$_apiBase/device-tokens'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': token,
          'platform': Platform.isAndroid ? 'android' : 'ios',
          'debug': isDebug,
        }),
      );
      debugPrint('[FCM] register response: ${res.statusCode} (debug=$isDebug)');
    } catch (e) {
      debugPrint('[FCM] register failed: $e');
    }

    // 포그라운드 메시지 → 로컬 알림으로 팝업 표시
    FirebaseMessaging.onMessage.listen((msg) async {
      final notif = msg.notification;
      debugPrint('[FCM] onMessage: ${notif?.title} - ${notif?.body}');
      if (notif == null) return;
      try {
        await _localNotifs.show(
          id: msg.hashCode,
          title: notif.title,
          body: notif.body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              importance: Importance.high,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
          ),
        );
      } catch (e) {
        debugPrint('[FCM] local show failed: $e');
      }
    });

    // 토큰 갱신 시 재등록 (릴리즈/디버그 모두)
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      debugPrint('[FCM] token refreshed');
      final isDebug = kDebugMode;
      try {
        await http.post(
          Uri.parse('$_apiBase/device-tokens'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'token': newToken,
            'platform': Platform.isAndroid ? 'android' : 'ios',
            'debug': isDebug,
          }),
        );
      } catch (_) {}
    });
  }
}
