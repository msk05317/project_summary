# Admin 의 '지금 어느 단계인가' 가 서버와 같은 답을 내는지
#   python3 backend/tests/test_mdl_group_now.py
#
# 두 곳이 어긋나면 Admin 과 앱이 다른 말을 한다.
import ast, datetime, json, os, pathlib, re, subprocess, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
HTML = (ROOT / 'admin_v2.html').read_text(encoding='utf-8')
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')

# 서버 쪽
tree = ast.parse(SRC)
srcs = {n.name: ast.get_source_segment(SRC, n) for n in tree.body
        if isinstance(n, ast.FunctionDef)
        and n.name in ('_display_group', '_norm_phases', '_phase_ord', '_as_money')}
g = {}
for n in ('_phase_ord', '_as_money', '_norm_phases', '_display_group'):
    exec(srcs[n], g)
py = g['_display_group']

ok = 0
# 연결부
assert 'window._mdlGroupNow(m)' in HTML, '필터가 _mdlGroupNow 를 안 쓴다'
assert HTML.count('window._mdlGroupNow(m)') >= 3, \
    '필터·그룹·드롭다운 세 곳 다 써야 한다'
ok += 1

if subprocess.run(['node', '--version'], capture_output=True).returncode != 0:
    print(f'전부 통과 ({ok}/{ok}) · node 없어 대조는 건너뜀'); raise SystemExit(0)

def grab(pat):
    i = HTML.index(pat)
    j = HTML.index('\n  }', i)
    return HTML[i:j + 4]

JS = '\n'.join([
    grab('function _curWeekTag()'),
    grab('function _phaseOrd(v)'),
    grab('function _phaseNorm(v)'),
    'function _moneyOf(v){ var n = parseFloat(String(v==null?"":v).replace(/[,\\s$₩]/g,""));'
    ' return (!isFinite(n)||n<0)?0:n; }',
    'var window = {};',
    grab('window._mdlGroupNow = function(m)'),
    'var CASES = __CASES__;',
    'console.log(JSON.stringify(CASES.map(function(m){ return window._mdlGroupNow(m); })));',
])

Y, W = datetime.date.today().isocalendar()[0], datetime.date.today().isocalendar()[1]
def wk(off):
    return '%04d-W%02d' % (Y, W + off)

CASES = [
    {'group': '개발'},
    {'group': '양산'},
    {},
    {'group': '개발', 'phases': [{'from': '%04d-W01' % Y, 'group': '개발', 'price': 1},
                                {'from': wk(-1), 'group': '양산', 'price': 2}]},
    {'group': '개발', 'phases': [{'from': '%04d-W01' % Y, 'group': '개발', 'price': 1},
                                {'from': wk(0), 'group': '양산', 'price': 2}]},
    {'group': '개발', 'phases': [{'from': '%04d-W01' % Y, 'group': '개발', 'price': 1},
                                {'from': wk(+3), 'group': '양산', 'price': 2}]},
    {'group': '양산', 'phases': [{'from': '%04d-W05' % (Y + 1), 'group': '개발', 'price': 1}]},
    {'group': '양산', 'phases': [{'from': '%04d-W01' % Y, 'group': '양산', 'price': 1},
                                {'from': wk(-2), 'group': '개발', 'price': 2}]},
    {'group': '개발', 'phases': 'x'},
    {'group': '개발', 'phases': [{'from': '없음', 'group': '양산'}]},
]
f = tempfile.NamedTemporaryFile('w', suffix='.js', delete=False, encoding='utf-8')
f.write(JS.replace('__CASES__', json.dumps(CASES, ensure_ascii=False))); f.close()
r = subprocess.run(['node', f.name], capture_output=True, text=True)
os.unlink(f.name)
assert r.returncode == 0, f'실행 실패\n{r.stderr[:700]}'
js = json.loads(r.stdout)
expect = [py(m) for m in CASES]
assert js == expect, f'Admin 과 서버가 다르다\n  admin  {js}\n  server {expect}'
ok += 1
assert expect[3] == '양산' and expect[5] == '개발', expect   # 판이 제대로 깔렸는지
ok += 1

print(f'전부 통과 ({ok}/3) · 경우 {len(CASES)}가지 서버와 일치')
