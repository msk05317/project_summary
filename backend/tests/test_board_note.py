# 보드 '비고' 칸 우선순위 검증
#   python3 backend/tests/test_board_note.py
#
# 직접 입력 > boards.json > 모델의 '그 외 특이사항 · 메모'(m['note'])
# '문제 · 리스크'(m['issues'])는 끌어오지 않는다.
import ast, pathlib

SRC = (pathlib.Path(__file__).resolve().parents[1] / 'main.py').read_text(encoding='utf-8')
tree = ast.parse(SRC)
src = next((ast.get_source_segment(SRC, n) for n in tree.body
            if isinstance(n, ast.FunctionDef) and n.name == '_board_row_note'), None)
assert src, '_board_row_note 를 못 찾았다'
g = {}
exec(src, g)
f = g['_board_row_note']

M002 = {'id': '715-044854-002', 'note': '제조일정 변경으로 중단 → 10월 재개', 'issues': '자재 지연'}
M205 = {'id': '715-181531-205', 'note': '305챔버로 변경 예정'}
BLANK = {'id': 'X', 'note': '', 'issues': '이건 비고가 아니다'}

ok = 0
assert f([M002], None, '손으로 적은 값') == '손으로 적은 값', '직접 입력이 최우선이어야 한다'
ok += 1
assert f([M002], 'boards.json 값', '') == 'boards.json 값', 'boards.json 이 모델보다 우선이어야 한다'
ok += 1
assert f([M002], None, None) == '제조일정 변경으로 중단 → 10월 재개', '모델 메모를 못 끌어왔다'
ok += 1
assert f([BLANK], None, None) == '', 'issues 를 비고로 끌어왔다'
ok += 1
assert f([], None, None) == '', '모델 없는 행이 빈칸이 아니다'
ok += 1
assert f(None, None, None) == '', 'models=None 에서 터졌다'
ok += 1

multi = f([M002, M205], None, None)
assert multi == ('715-044854-002: 제조일정 변경으로 중단 → 10월 재개\n'
                 '715-181531-205: 305챔버로 변경 예정'), f'여러 모델 표기가 다르다: {multi!r}'
ok += 1

dup = f([{'id': 'A', 'note': '같은 메모'}, {'id': 'B', 'note': '같은 메모'}], None, None)
assert dup == 'A: 같은 메모', f'같은 메모가 중복으로 나왔다: {dup!r}'
ok += 1

assert f([{'id': 'A', 'note': '  앞뒤 공백  '}], None, None) == '앞뒤 공백', '공백이 안 잘렸다'
ok += 1

# 실제 보드 조립부가 이 함수를 쓰는지
assert '_board_row_note(models, row.get("note"), man.get("note"))' in SRC, \
    '보드 조립부가 아직 옛날 방식이다'
ok += 1

print(f'전부 통과 ({ok}/10)')
