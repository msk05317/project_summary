// 사업부(division) 데이터 모델.
// 백엔드 GET /divisions 응답을 그대로 받기 위한 클래스들입니다.
// 응답 구조 예:
// {
//   "divisions": [
//     {
//       "id": "semiconductor",
//       "label": "반도체사업부",
//       "order": 1,
//       "badge_short_label": "반도체",
//       "projects": [ { "id": "frame", "label": "프레임", "order": 8 }, ... ]
//     },
//     ...
//   ]
// }

// 사업부 안의 프로젝트 한 칸을 표현하는 가벼운 참조 모델.
// 홈/목록 화면에서 "사업부 → 프로젝트" 그리드를 그릴 때 사용합니다.
class DivisionProjectRef {
  // 프로젝트 식별자 (예: 'frame')
  final String id;

  // 화면에 표시할 한글 이름 (예: '프레임')
  final String label;

  // 사업부 내에서의 정렬 순서. 작은 숫자가 먼저 표시됩니다.
  final int order;

  const DivisionProjectRef({
    required this.id,
    required this.label,
    required this.order,
  });

  // JSON → 모델 변환.
  // 안전을 위해 누락된 필드는 빈 문자열/0 으로 채웁니다.
  factory DivisionProjectRef.fromJson(Map<String, dynamic> j) {
    return DivisionProjectRef(
      id: (j['id'] ?? '').toString(),
      label: (j['label'] ?? '').toString(),
      order: (j['order'] is int) ? j['order'] as int : 0,
    );
  }
}

// 사업부 단위 모델.
// 사업부 자체의 정보 + 그 사업부에 속한 프로젝트 리스트를 담습니다.
class Division {
  // 사업부 식별자 (예: 'semiconductor')
  final String id;

  // 화면 표시용 풀네임 (예: '반도체사업부')
  final String label;

  // 짧은 라벨 (예: '반도체'). 카드 위 작은 배지 등에 사용합니다.
  final String? badgeShortLabel;

  // 사업부 정렬 순서.
  final int order;

  // 이 사업부에 속한 프로젝트들. order 기준으로 정렬된 상태로 보관합니다.
  final List<DivisionProjectRef> projects;

  const Division({
    required this.id,
    required this.label,
    required this.order,
    required this.projects,
    this.badgeShortLabel,
  });

  // JSON → 모델 변환.
  // projects 도 함께 파싱하고, order 기준 오름차순 정렬해 둡니다.
  factory Division.fromJson(Map<String, dynamic> j) {
    final list = (j['projects'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(DivisionProjectRef.fromJson)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    return Division(
      id: (j['id'] ?? '').toString(),
      label: (j['label'] ?? '').toString(),
      badgeShortLabel: j['badge_short_label']?.toString(),
      order: (j['order'] is int) ? j['order'] as int : 0,
      projects: list,
    );
  }
}
