// 적어 둔 이슈를 읽을 수 있는 줄로 쪼갠다.
//
// 담당자는 이슈를 엑셀 한 칸에 쉼표로 이어 적는다. 그대로 화면에 뿌리면
// 여섯 건이 한 덩어리로 흘러서 몇 건인지도 안 보인다. 줄로 끊어야 읽힌다.
//
//   PS 대체파트 미입고 2종 (W40), OEM 지연 1종 (W38), 33대 제조 완료,
//   FQC 불량, 고객 SR 승인 지연, 선적 스페이스 부족 이슈 미출하 (W38)
class IssueLine {
  /// 본문. 주차 표시는 떼어 낸다.
  final String text;

  /// 'W38' 처럼 끝에 붙어 있던 주차. 없으면 빈 문자열.
  final String week;

  const IssueLine(this.text, this.week);
}

class IssueText {
  /// 쉼표·줄바꿈·가운뎃점으로 끊어 한 줄씩.
  ///
  /// 쉼표를 무조건 끊지는 않는다. '2,000대' 처럼 숫자 사이의 쉼표까지
  /// 끊으면 말이 두 동강 난다.
  static List<IssueLine> split(String? raw) {
    final src = (raw ?? '').trim();
    if (src.isEmpty) return const [];

    // 숫자 사이 쉼표는 잠시 다른 글자로 감춰 둔다 (1,234)
    const guard = '';
    final safe = src.replaceAllMapped(
        RegExp(r'(\d),(\d)'), (m) => m[1]! + guard + m[2]!);

    final parts = safe
        // 가운뎃점은 글자 그대로 넣는다. r'\uB7' 로 적으면 네 자리가
        // 아니라서 정규식이 u · B · 7 을 각각 구분자로 먹는다
        // ('7월' → '월', 'BUS' → 'US' 가 됐다).
        .split(RegExp('[,\n;\u00B7]+'))
        .map((e) => e.replaceAll(guard, ',').trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final out = <IssueLine>[];
    for (final e in parts) {
      // 끝에 붙은 (W38) · (W38~W40) 같은 주차 표시를 떼어 낸다
      final m = RegExp(r'\(\s*[Ww]\s*(\d{1,2}(?:\s*[~-]\s*[Ww]?\s*\d{1,2})?)\s*\)$')
          .firstMatch(e);
      if (m == null) {
        out.add(IssueLine(e, ''));
        continue;
      }
      final body = e.substring(0, m.start).trim();
      final wk = 'W${m.group(1)!.replaceAll(' ', '')}';
      out.add(body.isEmpty ? IssueLine(e, '') : IssueLine(body, wk));
    }
    return out;
  }

  /// 줄 텍스트만 (주차를 뒤에 붙여서). 한 줄로 보여줄 자리에 쓴다.
  static List<String> lines(String? raw) => split(raw)
      .map((e) => e.week.isEmpty ? e.text : '${e.text} (${e.week})')
      .toList();
}
