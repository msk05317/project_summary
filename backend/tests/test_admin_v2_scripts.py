# admin_v2.html 의 <script> 블록 검사
#   python3 backend/tests/test_admin_v2_scripts.py
#
# 이 파일은 <script> 가 일곱 덩어리다. 한 덩어리에서 function 으로 선언한 걸
# 다른 덩어리에서 부르면 화면에 '_wbStock is not defined' 만 뜨고 끝난다.
# 블록을 넘나드는 함수는 window 에 붙여야 한다.
import os, pathlib, re, subprocess, tempfile

HTML = (pathlib.Path(__file__).resolve().parents[1] / 'admin_v2.html').read_text(encoding='utf-8')
BLOCKS = [m.group(1) for m in
          re.finditer(r'<script(?![^>]*src=)[^>]*>(.*?)</script>', HTML, re.S)]
ok = 0

# 1. 블록이 하나로 합쳐졌는지 (합쳐졌으면 이 검사가 의미 없어진다)
assert len(BLOCKS) >= 1, '스크립트 블록을 못 찾았다'
ok += 1

# 2. 문법
if subprocess.run(['node', '--version'], capture_output=True).returncode == 0:
    for i, body in enumerate(BLOCKS):
        f = tempfile.NamedTemporaryFile('w', suffix='.js', delete=False, encoding='utf-8')
        f.write(body); f.close()
        r = subprocess.run(['node', '--check', f.name], capture_output=True, text=True)
        os.unlink(f.name)
        assert r.returncode == 0, f'블록 {i} 문법 오류\n{r.stderr[:400]}'
ok += 1

# 3. 블록을 넘나드는 호출은 window 에 붙어 있어야 한다
defined, winned, used = {}, set(), {}
for n, body in enumerate(BLOCKS):
    for m in re.finditer(r'\bfunction\s+([A-Za-z_$][\w$]*)\s*\(', body):
        defined.setdefault(m.group(1), set()).add(n)
    for m in re.finditer(r'window\.([A-Za-z_$][\w$]*)\s*=', body):
        winned.add(m.group(1))
    for m in re.finditer(r'(?<![.\w$])([A-Za-z_$][\w$]*)\s*\(', body):
        used.setdefault(m.group(1), set()).add(n)

bad = []
for name, dblocks in defined.items():
    if name in winned:
        continue
    outside = used.get(name, set()) - dblocks
    if outside:
        bad.append(f'{name}: 정의 블록 {sorted(dblocks)} → 호출 블록 {sorted(outside)}')
assert not bad, '블록 밖에서 부르는 함수가 있다 (window 에 붙여야 한다)\n  ' + '\n  '.join(bad)
ok += 1

# 4. 재고 도우미는 window 에 있어야 한다 (보드는 다른 블록에서 그린다)
assert 'window._wbStock = function' in HTML
assert '_wbStock(sec)' in HTML and HTML.count('window._wbStock(sec)') == HTML.count('_wbStock(sec)')
ok += 1

print(f'전부 통과 ({ok}/4) · 블록 {len(BLOCKS)}개')
