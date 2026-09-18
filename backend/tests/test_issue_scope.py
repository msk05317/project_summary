# '일정 지연' 만 물으면 전 프로젝트를 훑는지
#   python3 backend/tests/test_issue_scope.py
#
# "일정 지연이 지금 여러개인데 왜 메이저모듈만 나오는거야"
#
# 세션에 남아 있던 마지막 프로젝트로 좁혀서 답하고 있었다. 홈에는
# '일정 지연 8건 · 3곳' 이라고 떠 있는데 챗은 메이저모듈 1건만 말하니
# 둘 중 무엇이 맞는지 알 수가 없었다.
import ast
import datetime
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)
ok = 0

WANT = {'_issue_answer_all', '_model_hold', '_model_alert', '_issue_says_delay',
        '_DELAY_NEG', '_display_project_label', '_load_models',
        '_process_step_done', '_display_group', '_parse_any_date',
        '_ensure_process', '_process_current', '_process_progress', 'SOON_DAYS'}
g = {'json': json, 'datetime': datetime}
for n in tree.body:
    if isinstance(n, ast.Assign) and getattr(n.targets[0], 'id', '') in WANT:
        try:
            exec(ast.get_source_segment(SRC, n), g)
        except Exception:
            pass
    if isinstance(n, ast.FunctionDef) and n.name in WANT:
        try:
            exec(ast.get_source_segment(SRC, n), g)
        except Exception:
            pass
assert '_issue_answer_all' in g, '_issue_answer_all 이 없다'

DATA = {'projects': {
    'a': {'models': [
        {'id': 'M1', 'name': 'EFEM', 'group': '개발', 'issues': '사급자재 지연'},
    ]},
    'b': {'models': [
        {'id': 'N1', 'name': '가', 'group': '양산', 'issues': '자재 입고 지연'},
        {'id': 'N2', 'name': '나', 'group': '양산', 'issues': '도면 변경'},
        {'id': 'N3', 'name': '다', 'group': '양산', 'issues': '검사 대기'},
        {'id': 'N4', 'name': '라', 'group': '양산', 'issues': '포장 지연'},
    ]},
    # 드롭·보류는 지연이 아니다
    'c': {'models': [
        {'id': 'H1', 'name': '멈춤', 'group': '양산', 'status': '보류',
         'issues': '고객 요청으로 중단'},
    ]},
    'bloom_x': {'models': [
        {'id': 'B1', 'name': '블룸', 'group': '양산', 'issues': '이건 안 나와야 한다'},
    ]},
    'empty': {'models': []},
}}
g['_load_models'] = lambda: DATA
g['_display_project_label'] = lambda k: {'a': '메이저모듈', 'b': '하바플레이트'}.get(k, k)

out = g['_issue_answer_all']()

# 한 곳만 말하지 않는다
assert '[메이저모듈] 1건' in out and '[하바플레이트] 4건' in out, out
assert out.startswith('일정 지연·이슈 5건 · 2곳.'), out
ok += 1

# 보류는 세지 않는다 — 멈춰 세운 것은 늦은 게 아니다
assert '멈춤' not in out and '고객 요청으로 중단' not in out, out
ok += 1

# 블룸은 일 보드라 여기서 빠진다
assert '블룸' not in out, out
ok += 1

# 프로젝트마다 세 줄까지, 나머지는 세어 준다
assert '· 외 1건' in out, out
_rows = [ln for ln in out.split('\n') if ln.startswith('· ')]
assert len(_rows) == 1 + 3 + 1, _rows      # a 1줄 + b 3줄 + '외 1건'
ok += 1

# 아무 데도 없으면 그렇다고 말한다
g['_load_models'] = lambda: {'projects': {}}
assert '없습니다' in g['_issue_answer_all']()
ok += 1

# ── 메시지에 프로젝트가 있으면 그 프로젝트만 ──
#
# 세션에 남은 값이 아니라 '이번 메시지' 에 이름이 있을 때만 좁힌다.
_br = SRC.split('# ── 이슈·지연 질문은 적힌 그대로 답한다')[1].split('# ── 월 범위 기억')[0]
assert '_proj_in_msg' in _br, '아직 세션 프로젝트로 좁힌다'
assert 'last_project' not in _br, '아직 세션 프로젝트를 본다'
assert '_issue_answer_all()' in _br, '전 프로젝트 경로가 없다'
ok += 1

print(f'전부 통과 · {ok}개 항목')
