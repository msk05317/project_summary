// 화면에 보이는 상태 이름.
//
// 서버가 쓰는 값('지연' · '이슈' · '임박' · '보류' · '정상')은 그대로 두고,
// 사람이 읽는 말만 여기서 정한다. 둘을 섞어 쓰면 화면마다 다른 말이 뜬다 —
// 홈은 '마감 임박', 목록은 '임박', 프로젝트는 '주의' 하는 식으로.
//
// '지연' 은 우리 잘못처럼 읽히고 '임박' 은 혼자 쓰면 광고 문구 같다.
// '이슈' 는 뜻이 너무 넓다. 그래서 일정 지연 · 집중관리 · 특이사항이다.
class StatusWords {
  /// 일정이 이미 밀린 것
  static const delayed = '일정 지연';

  /// 아직 안 늦었지만 며칠 안 남은 것
  static const soon = '집중관리';

  /// 목록 머리처럼 자리가 있을 때 쓰는 긴 말
  static const soonFull = '집중관리 (일정 임박)';

  /// 사람이 적어 둔 문제
  static const issue = '특이사항';

  /// 문제 없이 가고 있는 것
  static const normal = '정상';

  /// 멈춰 세운 것 (드롭예정 포함). 홈 타일에서는 뺐고, 모델 줄에는 남는다.
  static const hold = '보류';

  /// 서버 값 → 화면 말. 모르는 값은 그대로 쓴다 (드롭예정 · PO 대기 등).
  static String of(String kind) {
    switch (kind.trim()) {
      case '지연':
        return delayed;
      case '주의':
      case '임박':
      case '마감 임박':
        return soon;
      case '이슈':
        return issue;
      case '정상':
        return normal;
      default:
        return kind;
    }
  }
}
