import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chat_message.dart';

class ChatService {
  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://projectsummary-production.up.railway.app',
  );

  static Future<ChatMessage> ask(String message, {int topK = 5}) async {
    final uri = Uri.parse('$_baseUrl/chat');
    try {
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': message, 'top_k': topK}),
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
