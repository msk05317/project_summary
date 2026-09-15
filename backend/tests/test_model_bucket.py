# 앱 목록 필터: 지연 · 임박 · 진행 중 · 완료
#   python3 backend/tests/test_model_bucket.py
#
# 완료된 모델이 목록 맨 위에 계속 쌓여 있었다. 기본은 미완료만 보여주고,
# 지연·임박은 눌러서 따로 볼 수 있어야 한다.
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

# 기본은 완료 제외
v = D[D.index('List<Map<String, dynamic>> get _visible'):]
v = v[:v.index('\n  }')]
assert 'b != ModelBucket.done' in v, '기본 목록에서 완료를 안 뺀다'
ok += 1
# 급한 것부터
assert '_order.indexOf' in v, '정렬을 안 한다'
order = D[D.index('static const List<ModelBucket> _order'):]
order = order[:order.index('];')]
assert order.index('delayed') < order.index('soon') < order.index('running') < order.index('done'), order
ok += 1

# 칩 네 개
for label in ('미완료', '지연', '임박', '완료'):
    assert f"chip('{label}'" in D, f'{label} 칩이 없다'
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
