// 대시보드 응답 데이터 모델.
// 백엔드 GET /dashboard 의 응답을 그대로 받습니다.
// 응답에는 cards (개별 카드 단위)와 grouped_cards (모델 단위 묶음) 가 있는데,
// 홈 화면의 KPI/즉시확인 용으로는 cards 만 사용해도 충분합니다.

// 단일 신호등 카드.
// 한 프로젝트에 대한 상태(status), 마감일 후보(due_date_min),
// 요약 bullet 들이 담겨 있습니다.
class DashboardCard {
  // 프로젝트 식별자 (예: 'frame')
  final String projectKey;

  // 프로젝트 표시 이름
  final String projectLabel;

  // 사업부 식별자/이름
  final String divisionId;
  final String divisionLabel;

  // 상태 코드 (RED / ORANGE / YELLOW / GREEN / BLUE / GRAY / BLACK)
  final String status;

  // 가장 임박한 마감일 (없을 수 있음)
  final String? dueDateMin;

  // 보고일 (없을 수 있음)
  final String? reportDate;

  // 요약 bullet 텍스트들. "즉시 확인" 카드에 사용할 후보입니다.
  final List<String> summaryBullets;

  // 헤드라인 텍스트 (현재 응답에서는 대부분 빈 문자열로 옴)
  final String headline;

  // 실제 진행률 (출하/PO 기반, 없을 수 있음)
  final int? progress;

  const DashboardCard({
    required this.projectKey,
    required this.projectLabel,
    required this.divisionId,
    required this.divisionLabel,
    required this.status,
    required this.summaryBullets,
    this.dueDateMin,
    this.reportDate,
    this.headline = '',
    this.progress,
  });

  factory DashboardCard.fromJson(Map<String, dynamic> j) {
    final bullets = (j['summary_bullets'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();

    return DashboardCard(
      projectKey: (j['project_key'] ?? j['project_id'] ?? '').toString(),
      projectLabel: (j['project_label'] ?? j['project_badge'] ?? '').toString(),
      divisionId: (j['division_id'] ?? '').toString(),
      divisionLabel: (j['division_label'] ?? '').toString(),
      status: (j['status'] ?? 'GRAY').toString(),
      dueDateMin: j['due_date_min']?.toString(),
      reportDate: j['report_date']?.toString(),
      summaryBullets: bullets,
      progress: (j['progress'] as num?)?.toInt(),
      headline: (j['headline'] ?? '').toString(),
    );
  }
}

// 홈 화면 KPI 영역에 표시할 집계값.
// 시안 기준 4분할(진행 중 / 정상 / 주의 / 지연) + 전체 진행률(%) 입니다.
class DashboardSummary {
  // 전체 카드 수
  final int total;

  // RED 계열 = 지연
  final int delayed;

  // ORANGE/YELLOW 계열 = 주의
  final int warning;

  // GREEN 계열 = 정상
  final int normal;

  // GRAY/BLUE/BLACK 등 그 외 = 진행 중/대기 (현재 단계에서는 '진행 중' 으로 묶음)
  final int inProgress;

  // 데이터 미등록 (프로젝트 단위 집계에서만 사용)
  final int noData;

  // 프로젝트 단위 집계 여부. true 면 KPI 첫 칸이 '미등록' 으로 바뀐다.
  final bool byProject;

  // 진행률을 외부(모델 실데이터)에서 계산해 넘길 때 사용.
  final int? progressOverride;

  // 첫 KPI 칸 라벨 ('전체' / '사업부' 등)
  final String unitLabel;

  const DashboardSummary({
    required this.total,
    required this.delayed,
    required this.warning,
    required this.normal,
    required this.inProgress,
    this.noData = 0,
    this.byProject = false,
    this.progressOverride,
    this.unitLabel = '전체',
  });

  /// 프로젝트 단위 요약.
  /// - 전체(total) = 지연 + 주의 + 정상 (진행률 데이터가 있는 프로젝트)
  /// - 진행률은 모델 실데이터 가중 평균(progress)을 그대로 사용 (없으면 '-')
  factory DashboardSummary.fromProjects({
    required int delayed,
    required int warning,
    required int normal,
    required int noData,
    required int? progress,
  }) {
    return DashboardSummary(
      total: delayed + warning + normal,
      delayed: delayed,
      warning: warning,
      normal: normal,
      inProgress: 0,
      noData: noData,
      byProject: true,
      progressOverride: progress,
    );
  }

  /// 사업부 단위 요약.
  /// - 전체(total) = 등록된 사업부 수 (데이터 없는 사업부 포함)
  /// - 정상/주의/지연 = 데이터가 있는 사업부의 상태 분류
  /// - 진행률은 모델 실데이터 가중 평균(progress)
  factory DashboardSummary.fromDivisions({
    required int delayed,
    required int warning,
    required int normal,
    required int noData,
    required int? progress,
  }) {
    return DashboardSummary(
      total: delayed + warning + normal + noData,
      delayed: delayed,
      warning: warning,
      normal: normal,
      inProgress: 0,
      noData: noData,
      byProject: true,
      progressOverride: progress,
      unitLabel: '사업부',
    );
  }

  // 전체 진행률(%) 계산 (v2).
  //
  // 정의:
  // - 분자 = 정상(GREEN) + 진행 중(BLUE/GRAY/BLACK 등 그 외)
  // - 분모 = 전체 카드 수 (total)
  //
  // 의미: '지연(RED) 도 주의(YELLOW/ORANGE) 도 아닌 카드의 비율'.
  // 시안의 64% 같은 KPI 와 같은 톤(정상적으로 굴러가는 비율).
  //
  // 분모가 0(데이터 없음)이면 0 을 반환합니다.
  // - 화면에서 '-' 로 표시하려면 progressPercentOrNull 을 사용하세요.
  int get progressPercent {
    if (progressOverride != null) return progressOverride!;
    if (total == 0) return 0;
    final numerator = normal + inProgress;
    return ((numerator / total) * 100).round();
  }

  // 데이터가 없을 때 null 을 반환하는 버전.
  // - SummaryCard 에서 진행률을 '-' 로 표시할지, '0%' 로 표시할지 분기에 사용.
  int? get progressPercentOrNull {
    if (byProject) return progressOverride;
    if (total == 0) return null;
    return progressPercent;
  }

  // 카드 묶음(cards)에서 상태별로 카운팅해 요약을 생성합니다.
  factory DashboardSummary.fromCards(List<DashboardCard> cards) {
    int delayed = 0;
    int warning = 0;
    int normal = 0;
    int inProgress = 0;

    for (final c in cards) {
      switch (c.status.toUpperCase()) {
        case 'RED':
          delayed++;
          break;
        case 'ORANGE':
        case 'YELLOW':
          warning++;
          break;
        case 'GREEN':
          normal++;
          break;
        default:
          // BLUE / GRAY / BLACK / 빈값 → 진행 중/대기로 묶음
          inProgress++;
      }
    }

    return DashboardSummary(
      total: cards.length,
      delayed: delayed,
      warning: warning,
      normal: normal,
      inProgress: inProgress,
    );
  }
}

// ============================================================
// 사업부 카드 배지 상태 (4단계)
// 우선순위: delayed > warning > active > empty
// ============================================================
enum DivisionStatus { delayed, warning, active, empty }

DivisionStatus computeDivisionStatus(
  String divisionId,
  List<DashboardCard> cards,
) {
  var hasAny = false;
  var hasWarning = false;
  for (final c in cards) {
    if (c.divisionId != divisionId) continue;
    hasAny = true;
    final s = c.status.toUpperCase();
    if (s == 'RED') return DivisionStatus.delayed;
    if (s == 'YELLOW' || s == 'ORANGE') hasWarning = true;
  }
  if (hasWarning) return DivisionStatus.warning;
  if (hasAny) return DivisionStatus.active;
  return DivisionStatus.empty;
}
