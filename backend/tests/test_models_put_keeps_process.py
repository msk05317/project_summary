# 모델 관리 저장이 프로세스를 지우지 않는지 검증
#   python3 backend/tests/test_models_put_keeps_process.py
#
# 단계 수는 프로젝트마다 다르다 — 파워박스 15, EMA 14, 메이저모듈 12.
# 저장 코드가 12·13 만 인정하면, 엑셀로 넣은 14·15 단계가 이 화면을
# 저장하는 순간 빈 13단계 기본틀로 바뀐다.
import pathlib, re

SRC = (pathlib.Path(__file__).resolve().parents[1] / 'main.py').read_text(encoding='utf-8')
ok = 0

# 1. 길이로 프로세스를 버리는 코드가 남아 있으면 안 된다
bad = re.findall(r'len\(\s*_?proc\s*\)\s*in\s*\(\s*12\s*,\s*13\s*\)', SRC)
assert not bad, bad
ok += 1

# 2. 저장 경로는 '비어 있지 않으면 그대로' 여야 한다
assert 'entry["process"] = proc if isinstance(proc, list) and proc else _default_process()' in SRC
ok += 1
assert 'if isinstance(_proc, list) and _proc:\n                entry["process"] = _proc' in SRC
ok += 1

# 3. 저장 로직을 그대로 흉내 내어 14·15·12 단계가 살아남는지 본다
def keep(proc):
    return proc if isinstance(proc, list) and proc else ['기본'] * 13

for n in (12, 13, 14, 15):
    got = keep([{'key': f'step_{i+1}'} for i in range(n)])
    assert len(got) == n, (n, len(got))
ok += 1

# 4. 빈 것·리스트가 아닌 것만 기본틀로 간다
assert len(keep([])) == 13 and len(keep(None)) == 13
ok += 1

print(f'전부 통과 ({ok}/5)')
