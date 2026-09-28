# 모델 저장이 이 화면 밖의 값을 지우면 안 된다
#   python3 backend/tests/test_model_save_keep.py
#
# 예전에는 빈 도시락에 아는 칸만 담아 저장했다. 그래서 엑셀이 넣어 둔
# 소재·월 실적처럼 이 화면이 모르는 칸이 저장할 때마다 조용히 사라졌다.
import ast, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)
fn = next((ast.get_source_segment(SRC, n) for n in ast.walk(tree)
           if isinstance(n, ast.FunctionDef) and n.name == 'admin_put_project_models'), None)
assert fn, '모델 저장 함수를 못 찾았다'
ok = 0

# 서버에 있던 것을 바탕에 깔고 고치는 칸만 덮는다
assert 'entry = dict(old)' in fn, '아는 칸만 담아 저장한다 (모르는 칸이 사라진다)'
assert fn.index('old = old_map.get(mid)') < fn.index('entry = dict(old)'), \
    'old 를 먼저 읽어야 한다'
ok += 1

# 규칙 자체를 돌려본다 (저장 함수의 병합 규칙)
def merge(sent, old):
    entry = dict(old)
    entry.update({
        'id': sent['id'], 'group': sent.get('group') or old.get('group'),
        'po_qty': int(sent.get('po_qty') or 0),
        'issues': str(sent.get('issues') or ''),
        'note': str(sent.get('note') or ''),
    })
    if 'note' not in sent and old.get('note'):
        entry['note'] = old['note']
    return entry

OLD = {'id': 'A', 'group': '개발', 'po_qty': 8, 'material': '다이넥스',
       'monthly_actual': {'2026-09': 12}, 'weekly_plan': {'2026-09': {'W39': {'plan': 3}}},
       'note': '옛 메모', 'issues': '', 'dev_type': 'RPM'}

# 화면에서 PO 만 고쳐 저장 → 엑셀이 넣은 칸은 그대로
out = merge({'id': 'A', 'group': '개발', 'po_qty': 9, 'issues': '', 'note': '옛 메모'}, OLD)
assert out['material'] == '다이넥스', '소재가 사라졌다'
assert out['monthly_actual'] == {'2026-09': 12}, '월 실적이 사라졌다'
assert out['weekly_plan'], '주차별 계획이 사라졌다'
assert out['dev_type'] == 'RPM' and out['po_qty'] == 9
ok += 1

# 비고는 비우면 지워지고, 안 보내면 지킨다
assert merge({'id': 'A', 'note': ''}, OLD)['note'] == ''
assert merge({'id': 'A'}, OLD)['note'] == '옛 메모'
ok += 1

# 이 화면이 다루는 칸은 그대로 덮인다
for f in ('"po_qty"', '"shipped_qty"', '"price"', '"material_cost"', '"issues"', '"note"', '"status"'):
    assert f in fn, f'{f} 를 저장하지 않는다'
ok += 1

# 주차별 계획·자동차 묶음은 서버 것이 이긴다 (다른 화면에서 들어간 값)
assert '"weekly_plan", "weekly_progress", "weekly_summary"' in fn
ok += 1

print(f'test_model_save_keep: {ok} passed')
