class ReportItem {
  final String type;
  final String text;
  final String? dueDate;
  final String? photoRef;

  const ReportItem({
    required this.type,
    required this.text,
    this.dueDate,
    this.photoRef,
  });

  factory ReportItem.fromJson(Map<String, dynamic> j) {
    return ReportItem(
      type: (j['type'] ?? '').toString(),
      text: (j['text'] ?? '').toString(),
      dueDate: j['due_date']?.toString(),
      photoRef: j['photo_ref']?.toString(),
    );
  }
}

class ReportSection {
  final String title;
  final List<ReportItem> items;

  const ReportSection({
    required this.title,
    required this.items,
  });

  factory ReportSection.fromJson(Map<String, dynamic> j) {
    final list = (j['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ReportItem.fromJson)
        .toList();

    return ReportSection(
      title: (j['title'] ?? '').toString(),
      items: list,
    );
  }

  ReportItem? get firstPhoto {
    for (final item in items) {
      if (item.type == 'photo' && (item.photoRef?.isNotEmpty ?? false)) {
        return item;
      }
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
    );
  }

  ReportSection? get statusSection {
    for (final s in sections) {
      if (s.title == '현황') return s;
    }
    return null;
  }

  List<ReportSection> get bodySections {
    return sections.where((s) => s.title != '현황').toList();
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
