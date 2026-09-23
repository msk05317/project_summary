# admin '홈 관리' 화면 — 앱 홈에 뜨는 것을 한자리에서
#   python3 backend/tests/test_home_admin_ui.py
#
# 전사 화면이라 사이드바 사업부와 무관하다. 손으로 넣는 건 지시사항과
# 자료에 계획이 없는 사업부의 타겟뿐이고, 나머지는 확인만 한다.
import pathlib, re, subprocess, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = (ROOT / 'admin_v2.html').read_text(encoding='utf-8')
ok = 0

# ── 사이드바가 전사 / 사업부로 갈렸는지 ──
nav = SRC[SRC.index('<div class="nav-title">전사</div>'):SRC.index('<div class="spacer">')]
assert nav.index('data-page="homeadmin"') < nav.index('<div class="nav-title">사업부</div>'), \
    '홈 관리가 전사 묶음에 없다'
for pg in ('models', 'revenue'):
    assert nav.index('data-page="%s"' % pg) > nav.index('<div class="nav-title">사업부</div>'), \
        f'{pg} 가 사업부 묶음에 없다'
ok += 1

# ── 라우팅 · 이름표 ──
assert "homeadmin: '홈 관리'" in SRC
assert "if (pg === 'homeadmin')" in SRC and 'window.renderHomeAdmin()' in SRC
assert "_cb.textContent = '전사'" in SRC, '전사 화면인데 빵부스러기가 사업부 이름이다'
ok += 1

# ── 지시사항 편집 ──
assert "KINDS = [['date', '날짜까지'], ['none', '기한 없음'], ['daily', '매일'], ['weekly', '매주']]" in SRC
assert "fetch('/admin/home/orders'" in SRC and "method: 'PUT'" in SRC
# 완료하면 목록에서 내려간다
assert 'r.done = el.checked;' in SRC and 'repaintOrders();          // 완료는 목록에서 바로 내려간다' in SRC
assert '완료한 지시 ' in SRC and 'ha-done-toggle' in SRC
# 날짜는 '날짜까지' 일 때만
assert "if (r.due_kind !== 'date') r.due = '';" in SRC
assert "nd.disabled = nk.value !== 'date';" in SRC
ok += 1

# ── 꼬리표 규칙이 서버와 같은지 (지남 · 오늘 · D-n · 반복 · 등록일) ──
for t in ("'지남 · D+'", "'오늘 · '", "'D-'", "{ t: '매일', c: 'repeat' }", "' 등록'"):
    assert t in SRC, f'꼬리표 {t} 가 없다'
assert "c: n <= 3 ? 'late' : (n <= 7 ? 'warn' : 'plain')" in SRC, '3일 이내 빨강 규칙이 없다'
ok += 1

# ── 매출: 실적은 자동, 타겟만 입력. 자료에 계획이 있으면 그것도 자동 ──
assert 'r.target_editable' in SRC, '보고자료 계획이 있는 사업부까지 손으로 고치게 뒀다'
assert "fetch('/admin/home/division-target'" in SRC
assert '실적 출처' in SRC and '타겟 출처' in SRC
ok += 1

# ── 진행현황은 확인만 (입력 칸이 없어야 한다) ──
card = SRC[SRC.index("function statusCard()"):SRC.index("function previewCard()")]
assert '<input' not in card, '진행현황에 입력 칸이 있다 — 자동 집계여야 한다'
for col in ('정상', '지연', '특이사항', '집중관리'):
    assert col in card, f'{col} 열이 없다'
ok += 1

# ── 앱 미리보기 ──
assert 'function previewCard()' in SRC and 'ha-phone' in SRC
ok += 1

# ── 스크립트 블록 문법 ──
blocks = re.findall(r'<script[^>]*>(.*?)</script>', SRC, re.S)
with tempfile.TemporaryDirectory() as d:
    for i, b in enumerate(blocks):
        p = pathlib.Path(d) / f'b{i}.js'
        p.write_text(b, encoding='utf-8')
        r = subprocess.run(['node', '--check', str(p)], capture_output=True, text=True)
        assert r.returncode == 0, f'script[{i}] 문법 오류:\n{r.stderr[:400]}'
ok += 1

print(f'test_home_admin_ui: {ok} passed')
