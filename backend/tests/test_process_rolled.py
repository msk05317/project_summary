# 공정 '현재 위치' 판정 — 실적일이 찍힌 자리는 진행중이 아니다.
#   python3 backend/tests/test_process_rolled.py
#
# 파워박스 Striker Oxide 는 BV2 에 실적일(9/19)을 넣고도 상태가 '진행중' 으로
# 남아 있었다. _process_rolled 가 그 자리를 현재 위치로 잡는 바람에 뒤에 있는
# Source Inspection 을 무엇으로 바꾸든 화면은 늘 '대기' 였다 —
# 사용자 눈에는 '대기중으로 변경이 안 된다'.
# _process_current 는 이미 done 을 걸렀는데 _process_rolled 만 안 걸렀다.
import ast, pathlib

SRC = (pathlib.Path(__file__).resolve().parents[1] / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)
WANT = {'_process_rolled', '_process_step_done', '_process_step_active',
        '_process_progress', '_process_current'}
g = {}
for n in tree.body:
    if isinstance(n, ast.FunctionDef) and n.name in WANT:
        exec(ast.get_source_segment(SRC, n), g)
assert WANT <= set(g), f'못 찾은 함수: {WANT - set(g)}'
rolled, current = g['_process_rolled'], g['_process_current']
ok = 0

def st(name, actual='', status=''):
    return {'key': name, 'name': name, 'expected': '', 'actual': actual, 'status': status}

def names(proc):
    return {x['name']: x['status'] for x in rolled(proc)}

# ── 실제로 걸렸던 모양 ──
P = [
    st('FA PO', status='완료'), st('자재 발주', status='완료'),
    st('자재 입고', '2026-05-23', '완료'), st('CB', '2026-06-20', '완료'),
    st('BV1', '2026-07-04', '완료'),
    st('BV2', '2026-09-19', '진행중'),       # ← 실적일이 있는데 '진행중'
    st('LA 입고', status='완료'), st('LAIR 작성', status='대기'),
    st('LAIR 승인', status='대기'),
    st('Source Inspection', status='진행중'),
    st('FAIR 작성', status='대기'), st('최종 승인', status='대기'),
]
r = names(P)
assert r['BV2'] == '완료', f"실적일이 있는데 진행중으로 본다: {r['BV2']}"
assert r['Source Inspection'] == '진행중', \
    f"뒤 단계를 진행중으로 못 바꾼다: {r['Source Inspection']}"
assert r['FAIR 작성'] == '대기' and r['최종 승인'] == '대기'
ok += 1

# 현재 위치도 같은 자리여야 한다 (두 함수가 어긋나면 화면과 알림이 다르다)
assert current(P)[0] == 'Source Inspection', current(P)
ok += 1

# ── 그 자리를 '대기' 로 내리면 앞의 마지막 완료 자리로 돌아간다 ──
P2 = [dict(x) for x in P]
P2[9]['status'] = '대기'
r2 = names(P2)
assert r2['Source Inspection'] == '대기', f"대기로 안 내려간다: {r2['Source Inspection']}"
assert r2['BV2'] == '완료' and r2['LA 입고'] == '완료'
assert r2['LAIR 작성'] == '대기'
ok += 1

# ── 실적일 없는 '진행중' 은 그대로 현재 위치다 ──
P3 = [st('A', status='완료'), st('B', status='진행중'), st('C', status='대기')]
r3 = names(P3)
assert r3['B'] == '진행중' and r3['C'] == '대기' and r3['A'] == '완료', r3
ok += 1

# ── 진행중이 하나도 없으면 마지막 완료 자리 ──
P4 = [st('A', '2026-01-02'), st('B', '2026-02-03'), st('C'), st('D')]
r4 = names(P4)
assert r4['B'] == '완료' and r4['C'] == '대기' and r4['D'] == '대기', r4
ok += 1

# ── 진행률도 같은 규칙을 탄다 (뒤 단계는 안 센다) ──
prog = g['_process_progress']
assert prog(P) == round(9 / len(P) * 100), prog(P)
ok += 1

# ── admin 화면: 고른 값과 보이는 값이 다르면 이유를 말한다 ──
H = (pathlib.Path(__file__).resolve().parents[1] / 'admin_v2.html').read_text(encoding='utf-8')
assert '_now.status !== status' in H, '스냅된 값을 설명하지 않는다'
assert '공정은 순서대로라' in H
ok += 1

print(f'전부 통과 · {ok}개 항목')
