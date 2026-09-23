# admin_v2 모델 표 — 처음 보는 사람도 어느 칸에 무엇을 넣는지 알아야 한다.
#   python3 backend/tests/test_model_table_ui.py
#
# 머리줄 2단(묶음 + 칸 설명), 자동 계산 칸은 입력창이 아님, 상태는 모델명 옆 칩.
import pathlib, re, subprocess, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = (ROOT / 'admin_v2.html').read_text(encoding='utf-8')
ok = 0

# 머리줄 두 단
assert 'mdl-grp-row' in SRC and 'mdl-hd-row' in SRC, '머리줄이 두 단이 아니다'
for _g in ('모델', '분류', '금액 (USD · 1대 기준)', '수량 (대)', '메모'):
    assert _g in SRC, f'묶음 머리글 없음: {_g}'
ok += 1

# 칸마다 '무엇을 적는지' 한 줄
for _t, _d in [('판가', '고객 납품 단가'), ('재료비', '자재 합계'),
               ('PO 수량', '받은 발주'), ('실적 수량', '출하 완료'),
               ('이슈사항', '막힌 것 · 리스크'), ('비고', '그 외 메모')]:
    assert f"_hd('{_t}', '{_d}'" in SRC, f'{_t} 칸 설명이 없다'
ok += 1

# 자동 계산(재료비율 · 남은 수량)은 입력창이 아니다
assert 'data-field="ratio" class="mdl-auto' in SRC, '재료비율이 자동 계산 칸이 아니다'
assert 'data-field="remaining" class="mdl-auto"' in SRC, '남은 수량이 자동 계산 칸이 아니다'
assert '<td data-field="ratio"' not in SRC and 'mdl-td-ratio">\' + ratio' not in SRC
# 80% 주황 · 90% 빨강
assert "rt >= 90 ? ' mdl-auto-bad' : (rt >= 80 ? ' mdl-auto-warn' : '')" in SRC
ok += 1

# 상태는 열이 아니라 모델명 옆 칩
assert 'class="mdl-st-chip' in SRC, '상태 칩이 없다'
assert "'<th>모델명</th><th>구분</th><th>상태</th>" not in SRC, '상태 열이 남아 있다'
for _o in ('정상', '주의', '지연', '드롭예정', '보류'):
    assert _o in SRC
ok += 1

# 파트넘버는 모델명 칸 안으로
assert 'mdl-pn-input' in SRC and "'<th>파트넘버</th>'" not in SRC, '파트넘버 열이 남아 있다'
ok += 1

# 안내 문구 · 범례
assert '이 표는 무엇인가요' in SRC and 'mdl-guide' in SRC
assert '값을 눌러 바로 고칩니다' in SRC and '회색 점선 = 자동 계산' in SRC
ok += 1

# 빈 칸 예시 문구 (숫자 칸). 메모 칸은 머리글이 설명하므로 비워 둔다.
assert 'placeholder="예: 4800"' in SRC and 'placeholder="예: 4150"' in SRC
ok += 1

# 값은 글자처럼 보이고 누를 때만 칸이 된다 (상자 벽 방지)
assert '.mdl-table .mdl-input, .mdl-table .mdl-memo { background:transparent;' in SRC
ok += 1

# 일정 경고는 사람이 고르는 상태와 다른 것이라 따로 표를 단다
assert 'mdl-flag-late' in SRC and "'일정 지연'" in SRC
ok += 1

# 숫자는 천 단위 쉼표 (저장은 _rawNum 이 쉼표를 뗀다)
assert '_comma(price)' in SRC and "replace(/[,\\s$₩]/g, '')" in SRC
ok += 1

# 스크립트 블록 문법
blocks = re.findall(r'<script[^>]*>(.*?)</script>', SRC, re.S)
with tempfile.TemporaryDirectory() as d:
    for i, b in enumerate(blocks):
        p = pathlib.Path(d) / f'b{i}.js'
        p.write_text(b, encoding='utf-8')
        r = subprocess.run(['node', '--check', str(p)], capture_output=True, text=True)
        assert r.returncode == 0, f'script[{i}] 문법 오류:\n{r.stderr[:400]}'
ok += 1

print(f'test_model_table_ui: {ok} passed')
