import 'dart:convert';
import 'package:http/http.dart' as http;

class NotificationItem {
  final String id;
  final String ts;
  final String divisionId;
  final String title;
  final String projectKey;
  final String oldStatus;
  final String newStatus;
  final String triggerText;
  final String dueDate;
  final int? daysDiff;
  final String ddayLabel;
  final bool read;

  NotificationItem({
    required this.id,
    required this.ts,
    required this.divisionId,
    required this.title,
    required this.projectKey,
    required this.oldStatus,
    required this.newStatus,
    required this.triggerText,
    required this.dueDate,
    required this.daysDiff,
    required this.ddayLabel,
    required this.read,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> j) {
    return NotificationItem(
      id: (j['id'] ?? '').toString(),
      ts: (j['ts'] ?? '').toString(),
      divisionId: (j['division_id'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      projectKey: (j['project_key'] ?? '').toString(),
      oldStatus: (j['old_status'] ?? '').toString(),
      newStatus: (j['new_status'] ?? '').toString(),
      triggerText: (j['trigger_text'] ?? '').toString(),
      dueDate: (j['due_date'] ?? '').toString(),
      daysDiff: j['days_diff'] is int ? j['days_diff'] as int : null,
      ddayLabel: (j['dday_label'] ?? '').toString(),
      read: j['read'] == true,
    );
  }
}

class NotificationsResponse {
  final List<NotificationItem> items;
  final int unreadCount;
  NotificationsResponse({required this.items, required this.unreadCount});
}

class NotificationsService {
  static const String _apiBase = 'https://project-summary-mkoo.fly.dev';

  static Future<NotificationsResponse> list({int limit = 50}) async {
    final uri = Uri.parse('$_apiBase/notifications?limit=$limit');
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('알림 조회 실패: ${res.statusCode}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final rawItems = (data['items'] as List?) ?? [];
    final items = rawItems
        .whereType<Map<String, dynamic>>()
        .map(NotificationItem.fromJson)
        .toList();
    final unread = (data['unread_count'] ?? 0) as int;
    return NotificationsResponse(items: items, unreadCount: unread);
  }

  static Future<void> markRead(String id) async {
    final uri = Uri.parse('$_apiBase/notifications/$id/read');
    await http.post(uri);
  }

  static Future<void> markAllRead() async {
    final uri = Uri.parse('$_apiBase/notifications/read-all');
    await http.post(uri);
  }
}
