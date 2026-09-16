# 프로젝트 '확인 필요' 는 문제만 — 임박·비고는 '참고' 로 접는다
#   python3 backend/tests/test_check_section.py
#
# 하바는 비고를 상태 표시로 쓰고, 챔버는 이슈 칸을 비워두고 할 말을
# 전부 비고에 적는다. 그래서 비고를 확인 필요에 섞으면 23줄이 쏟아지고
# 정작 지연 3건이 묻힌다. "전체적인 내용이 다 올라와버리니까 문제야"
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
S = (ROOT.parent / 'mobile' / 'lib' / 'screens' /
     'project_overview_screen.dart').read_text(encoding='utf-8')
ok = 0

# ── 문제(0~2)와 참고(3~4)가 갈라져 있다 ──
assert 'bool get isProblem => rank <= 2;' in S, '문제/참고 구분이 없다'
assert 'all.where((r) => r.isProblem)' in S, '확인 필요가 문제만 세지 않는다'
assert 'all.where((r) => !r.isProblem)' in S, '참고 목록이 없다'
ok += 1

# ── 순서: 지연 → 이슈 → 보류 → 임박 → 비고 ──
import re
def rank_of(kind):
    # kind 배정 블록에서 그 종류의 rank 를 읽는다
    m = re.search(r"kind = %s;\s*\n\s*rank = (\d+);" % kind, S)
    assert m, f'{kind} 의 rank 를 못 찾았다'
    return int(m.group(1))
assert rank_of("'지연'") == 0
assert rank_of("'이슈'") == 1
assert rank_of("hold") == 2, '보류가 문제 쪽에 없다'
assert rank_of("'마감 임박'") == 3, '마감 임박이 아직 문제로 잡힌다'
assert rank_of("'비고'") == 4
ok += 1

# ── 이슈는 빨강. 파란색이면 '참고' 처럼 보인다 ──
m = re.search(r"case '이슈':\s*\n\s*return const Color\(0xFF(\w+)\);", S)
assert m and m.group(1) == 'DC2626', f'이슈 색이 {m and m.group(1)}'
ok += 1

# ── 같은 비고는 한 줄로 묶는다 ──
assert 'groups.putIfAbsent(r.lines.join' in S, '같은 비고를 안 묶는다'
assert '_sideGroupTile' in S and '외 ${names.length - 3}' in S, '묶어서 안 보여준다'
ok += 1

# ── 참고는 접혀 있다 ──
assert 'bool _sideOpen = false;' in S, '참고가 펼쳐진 채로 시작한다'
assert '_sideOpen ? Icons.expand_less : Icons.expand_more' in S
ok += 1

# ── 프로젝트째 보류면 같은 '보류' 를 29줄 늘어놓지 않는다 ──
assert "scope == 'project' && issues.isEmpty && note.isEmpty) continue" in S
ok += 1

# ── 문제가 없으면 '없음' 이라고 말한다 (빈 목록은 로딩과 구분이 안 된다) ──
assert '문제 없음' in S, '문제 0건일 때 아무 말도 안 한다'
ok += 1

print(f'전부 통과 · {ok}개 항목')
