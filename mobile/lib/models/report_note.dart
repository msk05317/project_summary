import 'profit_kpi_card.dart';
class TextRun {
  final String text;
  final String? color;      // hex e.g. "#002aff"
  final bool bold;
  final bool italic;
  final bool underline;
  final double sizeScale;   // 1.0 = 기본

  const TextRun({
    required this.text,
    this.color,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.sizeScale = 1.0,
  });

  factory TextRun.fromJson(Map<String, dynamic> j) => TextRun(
        text: (j['text'] ?? '').toString(),
        color: j['color']?.toString(),
        bold: j['bold'] == true,
        italic: j['italic'] == true,
        underline: j['underline'] == true,
        sizeScale: (j['size_scale'] as num?)?.toDouble() ?? 1.0,
      );
}

class ReportItem {
  final String type;
  final String text;
  final String? dueDate;
  final String? photoRef;
  final List<TextRun>? textRuns;

  const ReportItem({
    required this.type,
    required this.text,
    this.dueDate,
    this.photoRef,
    this.textRuns,
  });

  factory ReportItem.fromJson(Map<String, dynamic> j) {
    final rawRuns = j['text_runs'];
    List<TextRun>? runs;
    if (rawRuns is List) {
      runs = rawRuns
          .whereType<Map<String, dynamic>>()
          .map(TextRun.fromJson)
          .toList();
      if (runs.isEmpty) runs = null;
    }
    return ReportItem(
      type: (j['type'] ?? '').toString(),
      text: (j['text'] ?? '').toString(),
      dueDate: j['due_date']?.toString(),
      photoRef: j['photo_ref']?.toString(),
      textRuns: runs,
    );
  }
}

class ReportSection {
  final String title;
  final List<ReportItem> items;
  final String? salesSummary;
  final bool? salesVisible;
  final String? salesComputedAt;

  const ReportSection({
    required this.title,
    required this.items,
    this.salesSummary,
    this.salesVisible,
    this.salesComputedAt,
  });

  factory ReportSection.fromJson(Map<String, dynamic> j) {
    final list = (j['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ReportItem.fromJson)
        .toList();

    final rawSales = j['sales_summary'];
    final salesText = rawSales is String && rawSales.trim().isNotEmpty
        ? rawSales.trim()
        : null;

    return ReportSection(
      title: (j['title'] ?? '').toString(),
      items: list,
      salesSummary: salesText,
      salesVisible: (j['sales_visible'] is bool) ? j['sales_visible'] as bool : null,
      salesComputedAt: j['sales_computed_at'] as String?,
    );
  }

  static bool _isImageRef(String? ref, String? name) {
    // photoRef 자체가 이미지면 통과 (name은 표시용이라 xlsx여도 OK).
    // 백엔드는 xlsx도 PNG로 변환해 photoRef를 '.png'로 저장하므로
    // ref 기준으로만 판단해야 정당한 xlsx-프리뷰 표가 필터링되지 않음.
    final r = (ref ?? '').toLowerCase();
    if (r.isEmpty) {
      // ref가 비어있으면 name 확장자로만 판단 (fallback)
      final n = (name ?? '').toLowerCase();
      return n.endsWith('.png') ||
          n.endsWith('.jpg') ||
          n.endsWith('.jpeg') ||
          n.endsWith('.webp') ||
          n.endsWith('.gif');
    }
    return r.endsWith('.png') ||
        r.endsWith('.jpg') ||
        r.endsWith('.jpeg') ||
        r.endsWith('.webp') ||
        r.endsWith('.gif') ||
        r.contains('.png?') ||
        r.contains('.jpg?') ||
        r.contains('.jpeg?') ||
        r.contains('.webp?') ||
        r.contains('.gif?');
  }

  ReportItem? get firstPhoto {
    for (final item in items) {
      final isPhoto = item.type == 'photo' && (item.photoRef?.isNotEmpty ?? false);
      if (!isPhoto) continue;
      if (!_isImageRef(item.photoRef, item.text)) continue;
      return item;
    }
    return null;
  }
}

class ReportNote {
  final String projectKey;
  final String title;
  final String? status;
  final String? reportDate;
  final String? divisionId;
  final String? divisionLabel;
  final String? projectLabel;
  final String? updatedAt;
  final bool noteOnly;
  final List<ReportSection> sections;
  final ProfitKpiCard? kpiCard;
  final List<IssueLine> issueLines;

  const ReportNote({
    required this.projectKey,
    required this.title,
    required this.sections,
    this.status,
    this.reportDate,
    this.divisionId,
    this.divisionLabel,
    this.projectLabel,
    this.updatedAt,
    this.noteOnly = false,
    this.kpiCard,
    this.issueLines = const [],
  });

  factory ReportNote.fromJson(Map<String, dynamic> j) {
    // /projects/{project_key} 와 /notes/by_project 두 응답 형태를 모두 받기 위해
    // card 래퍼가 있으면 card 안을 사용하고, 없으면 루트 자체를 사용합니다.
    final root = (j['card'] is Map<String, dynamic>)
        ? (j['card'] as Map<String, dynamic>)
        : j;

    final sections = (root['sections'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ReportSection.fromJson)
        .toList();

    return ReportNote(
      projectKey: (j['project_key'] ?? j['project_id'] ?? root['project_key'] ?? '').toString(),
      title: (root['title'] ?? j['label'] ?? j['project_label'] ?? '').toString(),
      sections: sections,
      status: j['status']?.toString(),
      reportDate: (j['report_date'] ?? root['report_date'])?.toString(),
      divisionId: (j['division_id'] ?? root['division_id'])?.toString(),
      divisionLabel: (j['division_label'] ?? root['division_label'])?.toString(),
      projectLabel: (j['project_label'] ?? root['project_label'])?.toString(),
      updatedAt: (j['updated_at'] ?? root['updated_at'])?.toString(),
      noteOnly: (j['note_only'] == true),
      kpiCard: (j['kpi_card'] is Map<String, dynamic>)
          ? ProfitKpiCard.fromJson(Map<String, dynamic>.from(j['kpi_card']))
          : null,
      issueLines: (j['issue_lines'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => IssueLine.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  ReportSection? get statusSection {
    for (final s in sections) {
      if (s.title == '현황') return s;
    }
    return null;
  }

  List<ReportSection> get bodySections {
    // 현황 섹션도 다른 섹션과 동일하게 _ReportSectionCard로 렌더 (별 아이콘 제거).
    return sections.toList();
  }

  String? get summaryText {
    final s = statusSection;
    if (s == null) return null;

    for (final it in s.items) {
      if (it.type == 'highlight' && it.text.isNotEmpty) {
        return it.text;
      }
    }

    return s.items.isNotEmpty ? s.items.first.text : null;
  }
}
