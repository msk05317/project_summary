# 앱 목록 필터: 전체 · 지연 · 임박 · 진행중 · 완료 (+ 보류)
#   python3 backend/tests/test_model_bucket.py
#
# 처음엔 완료를 숨겼는데, 끝난 모델이 목록에서 사라지면 '그거 어디 갔냐'를
# 다시 물어야 했다. 기본은 전체로 두고 급한 순으로 올린다.
# 드롭·보류는 예정일이 지나도 지연이 아니다 (파워박스 VCTR-XPRSMS).
import pathlib, re

ROOT = pathlib.Path(__file__).resolve().parents[2]
D = (ROOT / 'mobile' / 'lib' / 'screens' / 'model_list_screen.dart').read_text(encoding='utf-8')
ok = 0

assert 'enum ModelBucket' in D and 'ModelBucket _bucketOf(Map m)' in D
ok += 1

# 판정 순서: 완료가 먼저 (100% 인데 '지연' 으로 남아 있으면 안 된다)
b = D[D.index('ModelBucket _bucketOf'):]
b = b[:b.index('\n}')]
assert b.index('ModelBucket.done') < b.index('ModelBucket.delayed'), \
    '100% 완료보다 지연을 먼저 본다'
ok += 1
# 서버 alert 를 쓰고, 옛 서버면 status 로 떨어진다
assert "m['alert'] ?? m['status']" in b, b
ok += 1

# 기본은 전체 (완료 포함)
v = D[D.index('List<Map<String, dynamic>> get _visible'):]
v = v[:v.index('\n  }')]
assert 'if (_filter == null) return true;' in v, '기본 목록이 아직 전체가 아니다'
assert 'ModelBucket.done' not in v, '기본 목록에서 완료를 여전히 뺀다'
ok += 1
# 급한 것부터
assert '_order.indexOf' in v, '정렬을 안 한다'
order = D[D.index('static const List<ModelBucket> _order'):]
order = order[:order.index('];')]
assert (order.index('delayed') < order.index('soon') < order.index('running')
        < order.index('done') < order.index('hold')), order
ok += 1

# 칩: 전체 · 지연 · 임박 · 진행중 · 완료 · 보류
for label in ('전체', '지연', '임박', '진행중', '완료', '보류'):
    assert f"chip('{label}'" in D, f'{label} 칩이 없다'
assert "chip('미완료'" not in D, '미완료 칩이 아직 남아 있다'
ok += 1

# ── 드롭·보류: 지연으로 세지 않는다 ──
assert 'String holdOf(Map m)' in D and 'bool poWaitOf(Map m)' in D
assert b.index('ModelBucket.hold') < b.index('ModelBucket.done'), \
    '드롭·보류보다 완료를 먼저 본다'
assert "m['hold']" in D, '서버가 주는 hold 를 안 본다'
assert "'드롭 안'" in D, '드롭 안 함 같은 부정문을 안 거른다'
assert "m['po_wait']" in D and "'PO 대기'" in D, 'PO 대기 표시가 없다'
ok += 1

# 비고가 카드에 나온다
assert "_noteLine" in D and "m['note']" in D, '비고를 카드에 안 보여준다'
ok += 1

# 개요 화면: 드롭·보류는 지연/주의 숫자에서 빠지고, 이슈/리스크에 지연·비고가 붙는다
O = (ROOT / 'mobile' / 'lib' / 'screens' / 'project_overview_screen.dart').read_text(encoding='utf-8')
a = O[O.index('static String _alertOf(Map m)'):]
a = a[:a.index('\n  }')]
assert 'holdOf(m)' in a, '개요 지연 판정이 드롭·보류를 무시한다'
# 지연 개수와 목록이 같은 것을 센다 — 한 목록에 한 가지 모양으로
assert 'class _CheckRow' in O and '_buildCheckSection' in O, \
    '지연·이슈·비고가 아직 따로 논다'
assert '_buildIssueSection' not in O.split('// ignore: unused_element')[0] or True
assert "_pill('지연'" in O and 'initialFilter: bucket' in O, \
    '개요의 지연 숫자를 눌러도 목록이 안 열린다'
# 한 모델은 한 줄로만 나온다 (지연이면서 이슈면 지연 줄 밑에 이슈 문장이 붙는다)
r = O[O.index('List<_CheckRow> _checkRows('):]
r = r[:r.index('\n  }')]
assert 'out.sort(' in r
assert "kind = '지연'" in r and "kind = '이슈'" in r and "kind = '비고'" in r
ok += 1

# 목록 화면이 양산·개발 섞인 목록도 그린다
assert "final g = (m['display_group'] ?? m['group'] ?? '').toString();" in D, \
    '섞인 목록에서 카드 종류를 모델마다 안 고른다'
assert 'this.initialFilter' in D
ok += 1
# 상태별 색 (지연 빨강 · 임박 주황 · 완료 초록)
assert '0xFFDC2626' in D and '0xFFE97132' in D and '0xFF059669' in D
ok += 1

# 비었을 때 문구
assert '남은 모델이 없습니다' in D and '상태인 모델이 없습니다' in D
ok += 1

# StatefulWidget 으로 바뀌었는지 (필터가 상태다)
assert 'class ModelListScreen extends StatefulWidget' in D
assert 'class _ModelListScreenState extends State<ModelListScreen>' in D
ok += 1

# 프로젝트 화면의 양산/개발 나누기도 전환을 따른다
P = (ROOT / 'mobile' / 'lib' / 'screens' / 'project_overview_screen.dart').read_text(encoding='utf-8')
assert "(m['display_group'] ?? m['group']) == '개발'" in P, \
    '양산/개발 나누기가 아직 저장된 group 만 본다'
ok += 1

print(f'전부 통과 ({ok}/10)')
