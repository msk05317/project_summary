class ProfitKpiEntry {
  final String label;
  final String type;
  final double efem;
  final double vtm;
  final double total;

  const ProfitKpiEntry({
    required this.label,
    required this.type,
    required this.efem,
    required this.vtm,
    required this.total,
  });

  bool get isActual => type == 'actual';
}

class ProfitKpiCard {
  final String title;
  final String metricMode;
  final String metricNote;
  final String unitLabel;
  final List<ProfitKpiEntry> months;
  final List<ProfitKpiEntry> weeks;
  final List<String> footnotes;

  const ProfitKpiCard({
    required this.title,
    required this.metricMode,
    required this.metricNote,
    required this.unitLabel,
    required this.months,
    required this.weeks,
    required this.footnotes,
  });

  factory ProfitKpiCard.fromJson(Map<String, dynamic> json) {
    double toD(dynamic v) => (v is num) ? v.toDouble() : 0.0;

    ProfitKpiEntry parse(Map<String, dynamic> m, String labelKey) {
      return ProfitKpiEntry(
        label: m[labelKey]?.toString() ?? '',
        type: m['type']?.toString() ?? 'plan',
        efem: toD(m['efem']),
        vtm: toD(m['vtm']),
        total: toD(m['total']),
      );
    }

    return ProfitKpiCard(
      title: (json['title'] ?? '월별/주차별 예상 이익').toString(),
      metricMode: (json['metric_mode'] ?? 'gross_profit').toString(),
      metricNote: (json['metric_note'] ?? '').toString(),
      unitLabel: (json['unit_label'] ?? '만불').toString(),
      months: (json['months'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => parse(Map<String, dynamic>.from(e), 'month'))
          .toList(),
      weeks: (json['weeks'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => parse(Map<String, dynamic>.from(e), 'week'))
          .toList(),
      footnotes: (json['footnotes'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class IssueLine {
  final String text;
  final String? dueDate;
  final String severity;
  final bool showDday;

  const IssueLine({
    required this.text,
    required this.severity,
    this.dueDate,
    this.showDday = false,
  });

  factory IssueLine.fromJson(Map<String, dynamic> j) {
    return IssueLine(
      text: (j['text'] ?? '').toString(),
      dueDate: j['due_date']?.toString(),
      severity: (j['severity'] ?? 'info').toString(),
      showDday: j['show_dday'] == true,
    );
  }
}
