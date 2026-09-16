# 엑셀 한 칸에 쉼표로 이어 적은 이슈를 줄로 끊는다
#   python3 backend/tests/test_issue_text.py
#
# "이슈사항 같은 경우에는 좀 깔끔하게 내용 정리좀 해줘"
#
# 실제 값이 이렇다. 여섯 건이 한 덩어리로 흘러서 몇 건인지도 안 보였다.
#   'PS 대체파트 미입고 2종 (W40), OEM 지연 1종 (W38),\n33대 제조 완료,
#    FQC 불량, 고객 SR 승인 지연, 선적 스페이스 부족 이슈 미출하 (W38)'
#
# 로직은 Dart 에 있어서(utils/issue_text.dart) 여기서는 같은 규칙을 파이썬으로
# 옮겨 돌려 보고, Dart 쪽에 그 규칙이 실제로 들어있는지 확인한다.
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = (ROOT.parent / 'mobile' / 'lib' / 'utils' / 'issue_text.dart').read_text(encoding='utf-8')
ok = 0

GUARD = ''


def split(raw):
    s = (raw or '').strip()
    if not s:
        return []
    s = re.sub(r'(\d),(\d)', lambda m: m.group(1) + GUARD + m.group(2), s)
    out = []
    for e in re.split(r'[,\n;·]+', s):
        e = e.replace(GUARD, ',').strip()
        if not e:
            continue
        m = re.search(r'\(\s*[Ww]\s*(\d{1,2}(?:\s*[~-]\s*[Ww]?\s*\d{1,2})?)\s*\)$', e)
        if not m:
            out.append((e, ''))
            continue
        body = e[:m.start()].strip()
        wk = 'W' + m.group(1).replace(' ', '')
        out.append((e, '') if not body else (body, wk))
    return out


# ── 실제 값이 여섯 줄로 끊긴다 ──
REAL = ('PS 대체파트 미입고 2종 (W40), OEM 지연 1종 (W38),\n'
        '33대 제조 완료, FQC 불량, 고객 SR 승인 지연, 선적 스페이스 부족 이슈 미출하 (W38)')
got = split(REAL)
assert len(got) == 6, got
assert got[0] == ('PS 대체파트 미입고 2종', 'W40'), got[0]
assert got[1] == ('OEM 지연 1종', 'W38'), got[1]
assert got[2] == ('33대 제조 완료', ''), got[2]
assert got[-1] == ('선적 스페이스 부족 이슈 미출하', 'W38'), got[-1]
ok += 1

# ── 숫자 사이 쉼표는 안 끊는다 ──
#   '2,000대' 를 끊으면 '2' 와 '000대' 로 말이 두 동강 난다
g = split('2,000대 미출하, 자재 1,500개 부족')
assert len(g) == 2, g
assert g[0][0] == '2,000대 미출하', g[0]
assert g[1][0] == '자재 1,500개 부족', g[1]
ok += 1

# ── 가운뎃점도 구분자 ──
assert len(split('자재 부족 · 선적 지연')) == 2
ok += 1

# ── 글자가 먹히면 안 된다 ──
#
# 가운뎃점을 r'\uB7' 로 적었더니 네 자리가 아니라서 정규식이 u · B · 7 을
# 각각 구분자로 먹었다. '7월' → '월', 'BUS' → 'US' 가 됐다.
for t in ('7월 물량 미출하', 'BUS 라인 정지', 'unit 교체', 'B타입 불량'):
    g = split(t)
    assert len(g) == 1 and g[0][0] == t, (t, g)
ok += 1

# Dart 쪽도 네 자리로 적혀 있어야 한다
assert r"\uB7]" not in SRC, "가운뎃점이 네 자리가 아니라 글자를 먹는다"
assert '\\u00B7' in SRC or '·' in SRC, '가운뎃점 구분자가 없다'
ok += 1

# ── 주차 범위도 뗀다 ──
g = split('선적 지연 (W38~W40)')
assert g == [('선적 지연', 'W38~W40')], g
ok += 1

# ── 빈 값 ──
assert split('') == [] and split(None) == [] and split('   ') == []
ok += 1

# ── 두 화면이 같은 걸 쓴다 ──
LIB = ROOT.parent / 'mobile' / 'lib'
ML = (LIB / 'screens' / 'model_list_screen.dart').read_text(encoding='utf-8')
PO = (LIB / 'screens' / 'project_overview_screen.dart').read_text(encoding='utf-8')
assert 'IssueText.split' in ML, '모델 상세가 아직 통으로 뿌린다'
assert 'IssueText.lines' in PO, '확인 필요가 아직 줄바꿈으로만 끊는다'
assert "issues.split('\\n')" not in ML and "issues.split('\\n')" not in PO
ok += 1

# ── 프로젝트 화면 맨 위에 이름이 있다 ──
#
# 홈에서 열면 projectName 을 빈 문자열로 넘겨서, 맨 위가 뒤로가기
# 화살표만 있는 빈 줄이었다. 무슨 프로젝트인지 알 수가 없었다.
assert 'String get _title' in PO, '이름이 없을 때 대비가 없다'
assert '목록 > ' in PO and 'Text(_title' in PO, '머리에 프로젝트 이름이 없다'
HOME = (LIB / 'screens' / 'home_screen.dart').read_text(encoding='utf-8')
assert "projectName: ''" not in HOME, '아직 빈 이름으로 연다'
assert '_openProject(String projectKey, [String projectName' in HOME
BOARD = (LIB / 'components' / 'home' / 'status_board_card.dart').read_text(encoding='utf-8')
assert 'onTapProject!(p.key, p.label)' in BOARD, '이름을 안 넘긴다'
ok += 1

print(f'전부 통과 · {ok}개 항목')
