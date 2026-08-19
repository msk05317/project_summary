// 프로젝트 요약 모델.
// 백엔드 GET /projects 응답의 한 항목을 그대로 받습니다.
// 사용처:
//  - 홈 화면의 "즐겨찾기 프로젝트" 카드
//  - 사업부 → 프로젝트 목록
//
// 응답 예:
// {
//   "key": "frame",
//   "label": "프레임",
//   "status": "RED",
//   "report_date": "2026-06-17",
//   "division_id": "semiconductor",
//   "division_label": "반도체사업부",
//   "project_id": "frame",
//   "project_label": "프레임",
//   "project_badge": "프레임"
// }

class ProjectSummary {
  // 프로젝트 식별자. 보고 상세 화면(ReportDetailScreen)에 그대로 전달됩니다.
  final String key;

  // 화면에 표시할 프로젝트 이름.
  final String label;

  // 상태 코드 ('RED' / 'YELLOW' / 'GREEN' / 'GRAY' / 'BLUE' / 'BLACK' 등).
  // 카드/배지 색을 결정하는 기준값입니다.
  final String? status;

  // 마지막 보고일 (yyyy-MM-dd). 카드 하단 보조 정보로 노출 가능.
  final String? reportDate;

  // 어느 사업부에 속해 있는지 식별자.
  final String? divisionId;

  // 어느 사업부에 속해 있는지 화면 표시용 이름.
  final String? divisionLabel;

  // 디자인 시안의 보조 배지 텍스트 (현재는 대부분 label 과 동일).
  final String? projectBadge;

  // 모델 데이터 유무 (서버에서 계산됨).
  final bool hasModels;

  // 모델 개수 (서버에서 계산됨).
  final int modelCount;

  const ProjectSummary({
    required this.key,
    required this.label,
    this.status,
    this.reportDate,
    this.divisionId,
    this.divisionLabel,
    this.projectBadge,
    this.hasModels = false,
    this.modelCount = 0,
  });

  // JSON → 모델 변환.
  // 백엔드가 'key' 대신 'project_key' / 'project_id' 로 내려주는 경우도
  // 안전하게 받아내기 위해 폴백을 둡니다.
  factory ProjectSummary.fromJson(Map<String, dynamic> j) {
    return ProjectSummary(
      key: (j['key'] ?? j['project_key'] ?? j['project_id'] ?? '').toString(),
      label: (j['label'] ?? j['project_label'] ?? '').toString(),
      status: j['status']?.toString(),
      hasModels: j['has_models'] as bool? ?? false,
      modelCount: (j['model_count'] as num?)?.toInt() ?? 0,
      reportDate: j['report_date']?.toString(),
      divisionId: j['division_id']?.toString(),
      divisionLabel: j['division_label']?.toString(),
      projectBadge: j['project_badge']?.toString(),
    );
  }
}
