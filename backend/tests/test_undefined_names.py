# 정의 안 된 이름이 새로 생기지 않았는지
#   python3 backend/tests/test_undefined_names.py
#   (pyflakes 가 없으면 건너뛴다: pip install pyflakes)
#
# 블룸 업로드가 배포된 뒤에야 "name 'openpyxl' is not defined" 로 터졌다.
# main.py 최상단에 openpyxl 이 없어서 쓰는 함수마다 직접 가져와야 하는데
# 한 군데를 빼먹었다. 문법 검사도 라우트 검사도 이걸 못 잡는다.
import pathlib, re, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]

# 이미 있던 것. 닿지 않는 코드(옛 RAG)라 지금 손대지 않는다.
KNOWN = {("main.py", "top_k")}

try:
    import pyflakes  # noqa: F401
except ImportError:
    print('pyflakes 가 없어 건너뜀 (pip install pyflakes)')
    raise SystemExit(0)

targets = sorted(p for p in ROOT.glob('*.py') if p.name != 'admin_v2.html')
found, checked = set(), 0
for path in targets:
    r = subprocess.run([sys.executable, '-m', 'pyflakes', str(path)],
                       capture_output=True, text=True)
    checked += 1
    for line in (r.stdout + r.stderr).splitlines():
        m = re.search(r"undefined name '([^']+)'", line)
        if m:
            found.add((path.name, m.group(1)))

new = sorted(found - KNOWN)
assert not new, (
    '정의 안 된 이름이 있습니다 — 배포하면 그 화면에서 터집니다:\n  ' +
    '\n  '.join(f'{f}: {n}' for f, n in new))

gone = sorted(KNOWN - found)
assert not gone, f'이미 고친 항목이 KNOWN 에 남아 있습니다: {gone}'

print(f'전부 통과 · 파일 {checked}개 · 알려진 예외 {len(KNOWN)}건 외에 없음')
