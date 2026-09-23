# admin_v2: 그룹 머리줄의 '지연' · '집중관리' 뱃지를 누르면 그 줄만 본다.
#   python3 backend/tests/test_model_alert_filter.py
#
# 44개 중 지연 15개를 찾으려고 표를 처음부터 훑던 일을 없앤다.
import pathlib, re, subprocess, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = (ROOT / 'admin_v2.html').read_text(encoding='utf-8')
ok = 0

assert 'window._mdlAlertPick = function(g, kind)' in SRC, '뱃지 누를 때 부를 함수가 없다'
assert SRC.count('window._mdlAlertPick(') >= 3, '뱃지 3개(지연·집중관리·전체 보기)에 onclick 이 안 붙었다'
for _k in ('지연', '주의'):
    assert ("_mdlAlertPick(\\'' + g + '\\', \\'" + _k) in SRC, f'{_k} 뱃지 onclick 이 없다'
ok += 1

# 뱃지를 누르면 그 종류만 남긴 목록으로 줄을 그린다
assert '_rows.forEach(function(m)' in SRC, '필터된 목록으로 안 그린다'
assert "_rows = _on === '지연' ? _late : (_on === '주의' ? _soon : list)" in SRC
ok += 1

# 해제 수단이 있다
assert '전체 보기' in SRC and 'mdl-badge-clear' in SRC, '필터 푸는 길이 없다'
ok += 1

# 프로젝트를 바꾸면 필터가 풀린다
assert 'window._mdlAlertFilterPk !== _pk' in SRC, '프로젝트 바꿔도 필터가 남는다'
ok += 1

# 스크립트 블록 문법 (인라인 onclick 따옴표를 깨먹기 쉬운 자리다)
blocks = re.findall(r'<script[^>]*>(.*?)</script>', SRC, re.S)
assert len(blocks) >= 5, len(blocks)
with tempfile.TemporaryDirectory() as d:
    for i, b in enumerate(blocks):
        p = pathlib.Path(d) / f'b{i}.js'
        p.write_text(b, encoding='utf-8')
        r = subprocess.run(['node', '--check', str(p)], capture_output=True, text=True)
        assert r.returncode == 0, f'script[{i}] 문법 오류:\n{r.stderr[:400]}'
ok += 1

print(f'test_model_alert_filter: {ok} passed')
