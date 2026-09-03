import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chat_message.dart';

class ChatService {
  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://project-summary-mkoo.fly.dev',
  );

  static Future<ChatMessage> ask(
    String message, {
    int topK = 5,
    List<Map<String, String>>? history,
    String sessionId = 'flutter_default',
  }) async {
    // 고정 sessionId면 랜덤 생성 (세션 오염 방지)
    if (sessionId == 'flutter_default') {
      sessionId = 'flutter_${DateTime.now().millisecondsSinceEpoch % 1000000}';
    }
    final uri = Uri.parse('$_baseUrl/chat');
    try {
      final payload = <String, dynamic>{
        'message': message,
        'top_k': topK,
        'session_id': sessionId,
      };
      if (history != null && history.isNotEmpty) {
        payload['history'] = history;
      }
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (resp.statusCode != 200) {
        return ChatMessage(
          role: ChatRole.assistant,
          text: '',
          error: 'HTTP ${resp.statusCode}',
        );
      }
      final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final answer = (j['answer'] ?? '').toString();
      final err = (j['error'] ?? '').toString();
      final sources = ((j['sources'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ChatSource.fromJson)
          .toList();
      return ChatMessage(
        role: ChatRole.assistant,
        text: answer,
        sources: sources,
        error: err.isEmpty ? null : err,
      );
    } catch (e) {
      return ChatMessage(
        role: ChatRole.assistant,
        text: '',
        error: '$e',
      );
    }
  }
}
