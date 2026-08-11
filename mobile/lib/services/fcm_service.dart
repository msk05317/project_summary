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

  // 알림 클릭 시 앱에서 처리할 콜백/데이터
  static Future<void> Function(Map<String, dynamic> data)? onUpdateNotificationTap;
  static Map<String, dynamic>? pendingOpenData;

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
      await _localNotifs.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (resp) {
          try {
            final payload = resp.payload;
            if (payload == null || payload.isEmpty) return;
            final data = Map<String, dynamic>.from(jsonDecode(payload));
            debugPrint('[FCM] local notif tapped: $data');
            _handleOpenData(data);
          } catch (e) {
            debugPrint('[FCM] local notif tap parse failed: $e');
          }
        },
      );
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

    // 포그라운드 메시지 → 로컬 알림으로 표시
    FirebaseMessaging.onMessage.listen((msg) async {
      final notif = msg.notification;
      debugPrint('[FCM] onMessage: ${notif?.title} - ${notif?.body}');
      if (notif == null) return;
      try {
        await _localNotifs.show(
          id: msg.hashCode,
          title: notif.title,
          body: notif.body,
          payload: jsonEncode(msg.data),
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

    // 앱이 백그라운드에 있다가 알림 클릭으로 열릴 때
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      debugPrint('[FCM] onMessageOpenedApp: ${msg.data}');
      _handleOpenData(msg.data);
    });

    // 앱이 완전 종료 상태에서 알림 클릭으로 실행될 때
    FirebaseMessaging.instance.getInitialMessage().then((msg) {
      if (msg != null) {
        debugPrint('[FCM] initialMessage: ${msg.data}');
        _handleOpenData(msg.data);
      }
    });

    // 토큰 갱신 시 재등록
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

  static void _handleOpenData(Map<String, dynamic> data) {
    pendingOpenData = data;
    final cb = onUpdateNotificationTap;
    if (cb != null) {
      cb(data);
    }
  }

  static Future<void> setUpdateTopic(bool subscribed) async {
    try {
      if (subscribed) {
        await FirebaseMessaging.instance.subscribeToTopic('update_notice');
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic('update_notice');
      }
    } catch (e) {
      debugPrint('FCM topic error: $e');
    }
  }
}
