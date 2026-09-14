# 블룸 일 보드가 admin_v2 에서 실제로 그려지는지
#   python3 backend/tests/test_bloom_admin_render.py
#
# 렌더러만 떼어 node 로 돌려 실제 HTML 을 본다.
import json, os, pathlib, re, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
HTML = (ROOT / 'admin_v2.html').read_text(encoding='utf-8')

# 블룸 블록 전체 (window.DAILY_BOARD_PROJECTS ~ _bdConfirm 끝)
m = re.search(r'(  window\.DAILY_BOARD_PROJECTS = .*?\n  \}\n)\n  window\.renderWeeklyBoard',
              HTML, re.S)
assert m, '블룸 블록을 못 찾았다'
BLOCK = m.group(1)

if subprocess.run(['node', '--version'], capture_output=True).returncode != 0:
    print('node 가 없어 건너뜀'); raise SystemExit(0)

BOARD = {
    "has_board": True, "prior_label": "9/9 이전 데이터", "file_name": "블룸_0914.xlsx",
    "dates": ["2026-09-13", "2026-09-14"],
    "report_date": "2026-09-14",
    "summary": {"date": "2026-09-14"},
    "notes": [{"eta": "9/16", "text": "KPE- 구매품 1종(퓨즈) ETA:9/16(2000set)"},
              {"eta": "", "text": "WDM- 금주중 입고 예정"}],
    "items": [
        {"item": "Corva KPE", "code": "172146 868000", "wait_ship": 80, "wait_part": 228,
         "steps": [
             {"step": "NCT(박닌)", "group": "NCT", "wip": 0, "month_plan": 1050,
              "month_actual": 233, "note": "",
              "days": {"2026-09-13": {"plan": 50, "actual": 31},
                       "2026-09-14": {"plan": 50, "actual": None}}},
             {"step": "조립(박닌)", "group": "조립", "wip": 20, "month_plan": 1050,
              "month_actual": 213, "note": "퓨즈 대기",
              "days": {"2026-09-13": {"plan": 50, "actual": 42},
                       "2026-09-14": {"plan": 50, "actual": None}}},
         ]},
        {"item": "BOP Assy", "code": "", "wait_ship": 5, "wait_part": 44,
         "steps": [
             {"step": "조립(박닌)", "group": "조립", "wip": 0, "month_plan": 1100,
              "month_actual": 1100, "note": "",
              "days": {"2026-09-14": {"plan": 55, "actual": 60}}},
         ]},
    ],
}

JS = """
var _h = '';
var document = { getElementById: function(){ return {
  set innerHTML(v){ _h = v; }, get innerHTML(){ return _h; },
  dataset:{}, style:{}, textContent:'' }; } };
var window = {};
var fetch = function(){ return { then: function(){ return this; }, catch: function(){ return this; } }; };
var alert = function(){}, confirm = function(){ return false; };
""" + BLOCK + """
var BOARD = __BOARD__;
var box = document.getElementById('wb-board');
_bdRender(box, BOARD);
console.log(JSON.stringify({html: box.innerHTML}));
""".replace('__BOARD__', json.dumps(BOARD))

f = tempfile.NamedTemporaryFile('w', suffix='.js', delete=False, encoding='utf-8')
f.write(JS); f.close()
r = subprocess.run(['node', f.name], capture_output=True, text=True)
os.unlink(f.name)
assert r.returncode == 0, f'렌더러 실행 실패\n{r.stderr[:800]}'
html = json.loads(r.stdout)['html']

ok = 0
# 품목·공정 이름은 엑셀에 적힌 그대로
assert 'Corva KPE' in html and 'NCT(박닌)' in html and '조립(박닌)' in html, html[:400]
ok += 1
assert '172146 868000' in html, '코드가 빠졌다'
ok += 1
# 날짜 머리글에 요일
assert '9/14 월' in html and '9/13 일' in html, html[:900]
ok += 1
# 기준일(9/14)만 빨간 테두리, 어제(9/13)는 아니다
import re as _re
heads = _re.findall(r'<th colspan="2"([^>]*)>([^<]+)</th>', html)
hmap = {t.strip(): a for a, t in heads}
assert 'bd-today' in hmap.get('9/14 월', ''), hmap
assert 'bd-today' not in hmap.get('9/13 일', 'x'), hmap
ok += 1
# 실적 미입력은 0 이 아니라 –
assert '–' in html, '미입력 표시가 없다'
ok += 1
# 계획 미달은 빨강, 초과 달성은 초록
assert 'bd-warn' in html and 'bd-ok' in html, '달성 색이 안 붙었다'
ok += 1
# 구매품 대기는 눈에 띄게
assert '228' in html, html[:600]
ok += 1
# 월 누적 달성률
assert '22%' in html, '월 누적 달성률(233/1050=22%)이 없다'
assert '100%' in html, 'BOP Assy 100% 가 없다'
ok += 1
# 합계 행 — 9/13 계획 50+50=100 실적 31+42=73, 9/14 계획 50+50+55=155 실적 60
assert 'bd-foot' in html, '합계 행이 없다'
_foot = html[html.index('bd-foot'):html.index('</tbody>')]
_nums = __import__('re').findall(r'>(\d+)</td>', _foot)
assert _nums == ['100', '73', '155', '60'], _nums
ok += 1
# 자재 ETA
assert '9/16' in html and '퓨즈' in html and '미정' in html, 'ETA 메모가 안 나온다'
ok += 1
# 비고
assert '퓨즈 대기' in html, '비고가 안 나온다'
ok += 1
# XSS 방어
assert '<script>' not in html
ok += 1

# 주차 보드로 새는지
assert "window._bdIsDaily(pk)" in HTML and "DAILY_BOARD_PROJECTS = ['bloom_main']" in HTML
ok += 1
print(f'전부 통과 ({ok}/13)')
