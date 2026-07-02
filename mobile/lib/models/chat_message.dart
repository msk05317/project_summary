class ChatSource {
  final String divisionId;
  final String projectLabel;
  final String projectKey;
  final String reportDate;
  final double score;

  const ChatSource({
    required this.divisionId,
    required this.projectLabel,
    required this.projectKey,
    required this.reportDate,
    required this.score,
  });

  factory ChatSource.fromJson(Map<String, dynamic> j) => ChatSource(
        divisionId: (j['division_id'] ?? '').toString(),
        projectLabel: (j['project_label'] ?? '').toString(),
        projectKey: (j['project_key'] ?? '').toString(),
        reportDate: (j['report_date'] ?? '').toString(),
        score: (j['score'] as num? ?? 0).toDouble(),
      );
}

enum ChatRole { user, assistant }

class ChatMessage {
  final ChatRole role;
  final String text;
  final List<ChatSource> sources;
  final bool loading;
  final String? error;
  final DateTime createdAt;

  ChatMessage({
    required this.role,
    required this.text,
    this.sources = const [],
    this.loading = false,
    this.error,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  ChatMessage copyWith({
    String? text,
    List<ChatSource>? sources,
    bool? loading,
    String? error,
  }) =>
      ChatMessage(
        role: role,
        text: text ?? this.text,
        sources: sources ?? this.sources,
        loading: loading ?? this.loading,
        error: error ?? this.error,
        createdAt: createdAt,
      );
}
