// 대시보드 카드 모델 + 상세 화면용 ProductDetail 모델

class ProductCard {
  final String docId;
  final String product;
  final String status;       // RED | BLUE | BLACK
  final String headline;
  final String reportDate;
  final String reportFamily;
  final String? projectKey;  // 부서 매핑 키 (chamber/powerbox/...)

  // 호환성 유지용 (기존 위젯이 참조)
  final String category;
  final int issueCount;

  ProductCard({
    required this.docId,
    required this.product,
    required this.status,
    required this.headline,
    required this.reportDate,
    required this.reportFamily,
    this.projectKey,
    this.category = '',
    this.issueCount = 0,
  });

  factory ProductCard.fromJson(Map<String, dynamic> json) {
    return ProductCard(
      docId: json['doc_id']?.toString() ?? '',
      product: json['product']?.toString() ?? '',
      status: json['status']?.toString() ?? 'BLACK',
      headline: json['headline']?.toString() ?? '',
      reportDate: json['report_date']?.toString() ?? '',
      reportFamily: json['report_family']?.toString() ?? '',
      projectKey: json['project_key']?.toString(),
      category: json['category']?.toString() ?? '',
      issueCount: (json['issue_count'] as int?) ?? 0,
    );
  }
}

// ============================================================
// 제품 상세 (fallback용 - project_key 없을 때만 사용)
// ============================================================
class ProductDetail {
  final String docId;
  final String product;
  final String status;
  final String headline;
  final String category;
  final String reportDate;
  final String reportFamily;
  final List<String> kpis;
  final List<String> criticalIssues;
  final List<String> milestones;
  final List<String> nextActions;
  final Map<String, dynamic> slideImages;
  final List<int> sourceSlideNumbers;

  ProductDetail({
    required this.docId,
    required this.product,
    required this.status,
    required this.headline,
    this.category = '',
    this.reportDate = '',
    this.reportFamily = '',
    this.kpis = const [],
    this.criticalIssues = const [],
    this.milestones = const [],
    this.nextActions = const [],
    this.slideImages = const {},
    this.sourceSlideNumbers = const [],
  });

  factory ProductDetail.fromJson(Map<String, dynamic> json) {
    return ProductDetail(
      docId: json['doc_id']?.toString() ?? '',
      product: (json['product'] ?? json['name'] ?? '').toString(),
      status: json['status']?.toString() ?? 'BLACK',
      headline: json['headline']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      reportDate: json['report_date']?.toString() ?? '',
      reportFamily: json['report_family']?.toString() ?? '',
      kpis: List<String>.from(
        (json['kpis'] as List?)?.map((e) => e.toString()) ?? [],
      ),
      criticalIssues: List<String>.from(
        (json['critical_issues'] as List?)?.map((e) => e.toString()) ?? [],
      ),
      milestones: List<String>.from(
        (json['milestones'] as List?)?.map((e) => e.toString()) ?? [],
      ),
      nextActions: List<String>.from(
        (json['next_actions'] as List?)?.map((e) => e.toString()) ?? [],
      ),
      slideImages: Map<String, dynamic>.from(json['slide_images'] ?? {}),
      sourceSlideNumbers: List<int>.from(
        (json['source_slide_numbers'] as List?)?.map((e) => e as int) ?? [],
      ),
    );
  }

  // 절대 URL로 변환된 슬라이드 이미지 리스트
  List<String> get slideImageUrls {
    const base = 'http://10.0.2.2:8000';
    if (sourceSlideNumbers.isNotEmpty && slideImages.isNotEmpty) {
      final urls = <String>[];
      final seen = <String>{};
      for (final num in sourceSlideNumbers) {
        final key = num.toString();
        if (seen.contains(key)) continue;
        seen.add(key);
        final url = slideImages[key];
        if (url != null) urls.add(_absoluteUrl(url.toString(), base));
      }
      if (urls.isNotEmpty) return urls;
    }
    final entries = slideImages.entries.toList()
      ..sort((a, b) =>
          (int.tryParse(a.key) ?? 0).compareTo(int.tryParse(b.key) ?? 0));
    return entries.map((e) => _absoluteUrl(e.value.toString(), base)).toList();
  }

  static String _absoluteUrl(String url, String base) {
    if (url.startsWith('http')) return url;
    if (url.startsWith('/')) return '$base$url';
    return '$base/$url';
  }
}
