# 모델 관리 프로젝트 카드 — 자동차는 진행률 대신 원가율
#   python3 backend/tests/test_admin_v2_picker.py
#
# admin_v2.html 에서 렌더러만 떼어 node 로 돌려 실제 출력 문자열을 본다.
import json, os, pathlib, re, subprocess, tempfile

HTML = (pathlib.Path(__file__).resolve().parents[1] / 'admin_v2.html').read_text(encoding='utf-8')
m = re.search(r'window\._mdlRenderPicker = function\(projects, stats, mode\) \{.*?\n    \};', HTML, re.S)
assert m, '_mdlRenderPicker(projects, stats, mode) 를 못 찾았다'

if subprocess.run(['node', '--version'], capture_output=True).returncode != 0:
    print('node 가 없어 건너뜀')
    raise SystemExit(0)

JS = '''
var _html = '';
var document = { getElementById: function() { return {
  set innerHTML(v) { _html = v; }, get innerHTML() { return _html; },
  querySelectorAll: function() { return { forEach: function() {} }; } }; } };
var window = {};
''' + m.group(0) + '''
var out = {};
window._mdlRenderPicker(
  [{id:'auto_kefico',label:'케피코'},{id:'auto_high_pressure_casting',label:'고압주조'}],
  {auto_kefico:{key:'auto_kefico',products:5,mass:1,dev:4,cost_ratio:0.9453},
   auto_high_pressure_casting:{key:'auto_high_pressure_casting',products:0,mass:0,dev:0,cost_ratio:null}},
  'auto');
out.auto = _html;
window._mdlRenderPicker([{id:'chamber',label:'챔버'}], {chamber:{models_total:23,progress:14}});
out.semi = _html;
window._mdlRenderPicker([{id:'plating_cell',label:'플레이팅 셀'}], {});
out.empty = _html;
// 값이 범위를 벗어나도 바가 안 터져야 한다
window._mdlRenderPicker([{id:'x',label:'X'}], {x:{products:1,cost_ratio:1.4}}, 'auto');
out.over = _html;
console.log(JSON.stringify(out));
'''
f = tempfile.NamedTemporaryFile('w', suffix='.js', delete=False, encoding='utf-8')
f.write(JS); f.close()
r = subprocess.run(['node', f.name], capture_output=True, text=True)
os.unlink(f.name)
assert r.returncode == 0, f'렌더러 실행 실패\n{r.stderr[:600]}'
out = json.loads(r.stdout)

def spans(s):
    return dict(re.findall(r'<span class="(nm|sub|pct)">(.*?)</span>', s)[:3])

def widths(s):
    return [float(x) for x in re.findall(r'width:([\d.]+)%', s)]

ok = 0
a = spans(out['auto'])
assert a['sub'] == '제품 5개 · 양산 1 · 개발 4', a
ok += 1
assert a['pct'] == '원가율 94.5%', a
ok += 1
assert round(widths(out['auto'])[0], 2) == 94.53, widths(out['auto'])
ok += 1

# 제품이 없는 자동차 프로젝트
assert '등록된 제품 없음' in out['auto'] and '원가율 -' in out['auto'], out['auto']
assert widths(out['auto'])[1] == 0
ok += 1

# 반도체는 그대로 진행률
sm = spans(out['semi'])
assert sm['sub'] == '모델 23개' and sm['pct'] == '진행률 14%', sm
ok += 1
assert '원가율' not in out['semi'], '반도체 카드에 원가율이 새어나왔다'
ok += 1

# 통계가 아예 없을 때
e = spans(out['empty'])
assert e['sub'] == '등록된 모델 없음' and e['pct'] == '진행률 -', e
ok += 1

# 100% 를 넘겨도 바는 100 에서 멈춘다
assert widths(out['over'])[0] == 100.0, widths(out['over'])
assert spans(out['over'])['pct'] == '원가율 140.0%', spans(out['over'])
ok += 1

# 자동차일 때 값을 받아오는 곳이 다른지
assert "'/divisions/automotive/summary'" in HTML and \
       "currentDiv === 'automotive'" in HTML, '자동차 분기가 없다'
ok += 1

print(f'전부 통과 ({ok}/9)')
