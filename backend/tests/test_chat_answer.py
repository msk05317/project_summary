# 챗봇이 프로젝트를 제대로 찾고, 짧게 답하는지
#   python3 backend/tests/test_chat_answer.py
#
# 배경: 경영진이 쓰는 챗봇인데 (1) 블룸·큐리를 프로젝트로 인식 못 해
# '어떤 기준의 총액이 궁금하신가요?' 로 떨어지고, (2) 벡터 검색은
# return 뒤에 있어 한 번도 실행된 적이 없었다.
import ast, json, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)
ok = 0


def load(names, extra=None):
    g = dict(extra or {})
    want = set(names)
    for n in tree.body:
        if isinstance(n, ast.Assign) and getattr(n.targets[0], 'id', '') in want:
            exec(ast.get_source_segment(SRC, n), g)
        if isinstance(n, ast.FunctionDef) and n.name in want:
            exec(ast.get_source_segment(SRC, n), g)
    missing = want - set(g)
    assert not missing, f'못 찾은 이름: {missing}'
    return g


# ── 1) 프로젝트 매핑: projects.json 의 aliases/keywords 를 전부 본다 ──
g = load(['_CHAT_PROJ_KW_CACHE', '_CHAT_KW_EXTRA',
          '_chat_project_keywords', '_chat_resolve_project'])
import sys
sys.path.insert(0, str(ROOT))
resolve = g['_chat_resolve_project']

CASES = [
    ('파워박스 매출 얼마야', 'powerbox'),
    ('블룸 오늘 실적 어때', 'bloom_main'),
    ('큐리 진행 상황 알려줘', 'spacex'),        # '큐리' 는 예전에 못 잡았다
    ('하바플레이트 지연', 'hrva_plate'),
    ('YFP 오늘 계획', 'bloom_yfp'),
    ('BOP Assy 실적', 'bloom_bop_assy'),
    ('SL7 어제 실적', 'bloom_sl7'),
    ('메이저모듈 8월', 'major_module'),
    ('프레임 진행률', 'frame'),
    ('이번주 매출 얼마야', None),               # 프로젝트가 없으면 None
]
for q, want in CASES:
    got = resolve(q)
    assert got == want, f'{q!r} → {got} (기대 {want})'
    ok += 1

# 짧은 영문 약어는 단어 경계로만 잡는다 (TC 가 아무 데나 붙으면 안 된다)
assert resolve('batch 파일 확인') != 'bloom_tc'
ok += 1

# ── 2) 되묻기 문구가 사라졌다 ──
assert '어떤 기준의 총액이 궁금하신가요' not in SRC, '되묻기가 아직 남아 있다'
assert '기준 미지정 → 이번 달' in SRC, '기본 기간(이번 달) 처리가 없다'
ok += 1

# ── 3) 옛 RAG 죽은 코드가 없고, 살아 있는 경로가 생겼다 ──
assert '_vs.search(message, top_k=top_k)' not in SRC, '닿지 않는 옛 RAG 가 남아 있다'
for name in ('_rag_context', '_rag_rebuild', '_rag_build_chunks', '_rag_maybe_refresh'):
    assert f'def {name}(' in SRC, f'{name} 가 없다'
assert '_rag_context(_user_text)' in SRC, 'RAG 가 /chat 에 연결되지 않았다'
ok += 1

# 인덱스가 없으면 조용히 빈 문자열 (예전과 똑같이 동작)
rg = load(['_rag_context'], {'_vs': type('V', (), {
    'is_ready': staticmethod(lambda: False),
    'search': staticmethod(lambda *a, **k: [])})()})
assert rg['_rag_context']('아무거나') == ''
ok += 1

# ── 4) 답변이 짧다: 월/주차 즉답은 주차별 목록을 기본으로 붙이지 않는다 ──
assert 'with_weeks=False' in SRC, '주차별 목록이 여전히 기본이다'
assert SRC.count("lines.append('주차별 (실적 / 계획)')") == 1
assert 'max_tokens=320' in SRC, 'LLM 답변 길이 제한이 안 걸렸다'
assert '최대 2문장' in SRC, '간결 규칙이 프롬프트에 없다'
ok += 1

# ── 5) 군더더기 제거가 본문을 먹지 않는다 ──
st = load(['_strip_useless_caveats'])['_strip_useless_caveats']
assert st('W38 파워박스 매출 실적 $0 / 계획 $821,322.') == \
    'W38 파워박스 매출 실적 $0 / 계획 $821,322.'
assert '879,528' in st('확인해 보니, 9월 누적 실적은 $879,528입니다.')
assert '1,234,567' in st('말씀하신 파워박스 매출은 $1,234,567입니다. 더 궁금한 점 있으시면 말씀해 주세요.')
assert st('안녕하세요') == '안녕하세요'
ok += 1

# ── 6) 블룸 즉답: 실적 입력 전이면 계획만, 품목 메모만 ──
b = load(['_bloom_summary', '_bloom_slice', '_bloom_item_totals',
          '_bloom_board_for', '_bloom_chat_answer', '_bloom_item_of', '_norm_label',
          '_kmonth'])
BOARD = {
    'dates': ['2026-09-14', '2026-09-15'],
    'items': [
        {'item': 'YFP', 'steps': [{'group': 'NCT', 'days': {
            '2026-09-14': {'plan': 10, 'actual': 8},
            '2026-09-15': {'plan': 12}}}]},
        {'item': 'SL7', 'steps': [{'group': '조립', 'days': {
            '2026-09-14': {'plan': 20, 'actual': 20},
            '2026-09-15': {'plan': 30}}}]},
    ],
    'notes': [{'text': 'SL7- 터미널 블록 ETA: 9/18'},
              {'text': 'KPE- 퓨즈 ETA: 9/16'}],
}
CFG = {'bloom_main': {}, 'bloom_yfp': {'bloom_item': 'YFP', 'label': 'YFP'},
       'bloom_sl7': {'bloom_item': 'SL7', 'label': 'SL7'}}
b['_load_models'] = lambda: {'projects': {'bloom_main': {'daily_board': BOARD}}}
b['_model_key_alias'] = lambda k: k
b['_BLOOM_STORE'] = 'bloom_main'
b['_cl'] = type('C', (), {'get_project': staticmethod(lambda k: CFG.get(k))})()
ans = b['_bloom_chat_answer']

a = ans('bloom_main', '9/14 실적')      # 어제 = 실적 있는 날
assert '9/14' in a and '28/30' in a, a
ok += 1

a2 = ans('bloom_main', '오늘 실적')      # 9/15 = 실적 입력 전
assert '입력 전' in a2 and '계획 42대' in a2, a2
assert '0/12' not in a2, '실적 입력 전인데 0/N 으로 보여준다'
assert '직전 9/14 실적 28/30대' in a2, a2
ok += 1

a3 = ans('bloom_sl7', '오늘')            # 품목 프로젝트는 자기 메모만
assert 'SL7- 터미널 블록' in a3, a3
assert 'KPE-' not in a3, '남의 품목 메모가 붙었다'
ok += 1

assert b['_kmonth']('2026-09') == '9월'
ok += 1

# ── 7) 이슈 답변이 중간에서 끊기지 않는다 ──
#   80자에서 자른 컨텍스트를 받은 LLM 이 '선적 스페이스 부' 에서 문장을 멈췄다.
assert "m.get('issues')[:80]" not in SRC, '이슈 컨텍스트가 아직 80자에서 잘린다'
# 프로젝트를 안 짚으면 전 프로젝트를 훑는다 (test_issue_scope.py 참고).
assert '_issue_answer(_proj_in_msg) if _one else _alert_answer_all(_kinds)' in SRC, \
    '이슈 즉답이 /chat 에 연결되지 않았다'

iss = load(['_issue_answer', '_display_project_label', '_model_alert', '_display_group', '_norm_phases',
            '_phase_ord', '_as_money', '_process_step_done', '_model_hold',
            '_project_hold', '_project_hold_reason', '_hold_from_note',
            '_CHAT_KW_EXTRA',
            '_HOLD_WORDS', '_HOLD_NEGATIONS'])
LONG = ('PS 대체파트 미입고 2종 (W40), OEM 지연 1종 (W38),\n'
        '33대 제조 완료, FQC 불량, 고객 SR 승인 지연, 선적 스페이스 부족 이슈 미출하 (W38)')
iss['_load_models'] = lambda: {'projects': {'powerbox': {'models': [
    {'id': '925-800083-394', 'name': 'PS', 'issues': LONG, 'group': '양산'},
    {'id': '000-1', 'name': '정상품', 'group': '양산'}]}}}
iss['_model_key_alias'] = lambda k: k
iss['PROJECT_LABELS'] = {'powerbox': '파워박스'}
a = iss['_issue_answer']('powerbox')
assert '선적 스페이스 부족 이슈 미출하 (W38)' in a, f'이슈가 잘렸다: {a}'
assert a.count('·') == 1, f'이슈 없는 모델까지 나왔다: {a}'
assert '(W38), /' not in a, f'줄 끝 쉼표가 남았다: {a}'
ok += 1

iss['_load_models'] = lambda: {'projects': {'frame': {'models': [{'id': 'x', 'group': '양산'}]}}}
iss['PROJECT_LABELS'] = {'frame': '프레임'}
assert '없습니다' in iss['_issue_answer']('frame')
ok += 1

print(f'전부 통과 · {ok}개 항목')
