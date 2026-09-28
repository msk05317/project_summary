# 같은 주소를 두 번 등록하지 않는다
#   python3 backend/tests/test_no_dup_routes.py
#
# 매입 엑셀 올리기가 main.py 에 두 벌 있었다. FastAPI 는 먼저 등록된
# 것을 쓰기 때문에, 나중에 붙인 쪽을 아무리 고쳐도 화면은 앞의 것을
# 불렀다. 500 이 떠서 서버 로그를 보고 나서야 알았다.
#
#   AttributeError: module 'purchase_import' has no attribute 'diff'
#
# 두 벌이 생긴 순간에 잡혔으면 그 한 시간을 안 썼다.
import ast
import collections
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
METHODS = ('get', 'post', 'put', 'delete', 'patch')

seen = collections.Counter()
where = collections.defaultdict(list)

for n in ast.walk(ast.parse(SRC)):
    if not isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
        continue
    for d in n.decorator_list:
        if not isinstance(d, ast.Call):
            continue
        f = d.func
        if not (isinstance(f, ast.Attribute) and isinstance(f.value, ast.Name)
                and f.value.id == 'app' and f.attr in METHODS):
            continue
        if d.args and isinstance(d.args[0], ast.Constant) \
                and isinstance(d.args[0].value, str):
            key = (f.attr.upper(), d.args[0].value)
            seen[key] += 1
            where[key].append('%s (main.py:%d)' % (n.name, n.lineno))

assert seen, '라우트를 하나도 못 찾았다 — 이 테스트가 헛돌고 있다'

dups = {k: v for k, v in seen.items() if v > 1}
if dups:
    lines = []
    for (m, path), cnt in sorted(dups.items()):
        lines.append('  %s %s — %d벌' % (m, path, cnt))
        for w in where[(m, path)]:
            lines.append('      ' + w)
    raise SystemExit('같은 주소가 두 번 등록됐다. 앞의 것만 살고 뒤는 죽는다:\n'
                     + '\n'.join(lines))

print('전부 통과 · 라우트 %d개, 중복 없음' % sum(seen.values()))
