// ============================================================
// File: lib/utils/report_summary.dart
// Section: Report / Summary extractor
// 역할:    /notes/by_project 응답의 card.sections 에서
//          "현황" 섹션의 첫 번째 highlight 문구를 뽑아낸다.
// 출력:    ReportSummary(text, dueDate?)  또는 null
// 사용처:  보고 상세 화면이 StatusSummaryCard 에 넘겨줄 텍스트 생성
// ============================================================

class ReportSummary {
  // 화면에 띄울 한 줄 (예: '총 42개 모델 중 양산 2종, 진행중 40종')
  final String text;

  // 백엔드가 주는 마감일 (선택)
  final String? dueDate;

  const ReportSummary({
    required this.text,
    this.dueDate,
  });
}

/// /notes/by_project 응답을 그대로 받아서 ★ 한 줄 정보를 뽑는다.
///
/// 입력 예: {
///   "card": {
///     "sections": [
///       {"title": "현황", "items": [{"type":"highlight","text":"..."}]}
///     ]
///   }
/// }
ReportSummary? extractStatusSummary(Map<String, dynamic> noteJson) {
  final card = noteJson['card'];
  if (card is! Map) return null;

  final sections = card['sections'];
  if (sections is! List) return null;

  for (final s in sections) {
    if (s is! Map) continue;
    final title = (s['title'] ?? '').toString();
    if (title != '현황') continue;

    final items = s['items'];
    if (items is! List) continue;

    for (final it in items) {
      if (it is! Map) continue;
      if ((it['type'] ?? '').toString() != 'highlight') continue;

      final text = (it['text'] ?? '').toString();
      if (text.isEmpty) continue;

      final due = it['due_date']?.toString();
      return ReportSummary(text: text, dueDate: due);
    }
  }

  return null;
}
