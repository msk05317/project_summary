# -*- coding: utf-8 -*-
"""저장은 중간이 없어야 한다.
   python3 backend/tests/test_atomic_save.py

데이터 전체가 models.json 파일 하나에 들어 있다. 운영 파일을 직접 열어서
쓰면(open "w"), 쓰는 도중에 서버가 죽거나 배포로 교체될 때 JSON 이 반만
적힌 파일이 남는다. 반만 적힌 JSON 은 다시 읽을 수 없고, 서버가 올라오면서
"운영 데이터가 없습니다" 로 빠져 씨앗 파일로 돌아간다. 289개 모델이
사라진 것처럼 보이는 상황이다.

엑셀 업로드 한 번이 전체를 다시 쓰는 구조라 쓰는 시간도 짧지 않다.
그만큼 그 사이에 죽을 틈이 있다.

그래서 옆에 다 쓰고 → 디스크에 앉히고(flush + fsync) → os.replace 로
이름만 바꾼다. replace 는 같은 파일 시스템 안에서 원자적이라, 어느 순간에
죽어도 파일은 '옛날 것' 아니면 '새 것'이지 중간이 없다.

여기서 지키는 것
  · _save_models 가 운영 파일을 직접 열지 않는다
  · 임시 파일에 쓰고 os.replace 로 바꾼다
  · fsync 로 디스크에 앉히고 나서 바꾼다
  · 직전 사본(.auto_*)은 그대로 남아 있다 — 다른 일을 하는 장치다
  · 실제로 돌려 봐도 중간 상태가 안 보인다
"""
import ast
import json
import os
import sys
import tempfile
from pathlib import Path

BACK = Path(__file__).resolve().parent.parent
SRC = (BACK / "main.py").read_text(encoding="utf-8")

FAIL = []


def ok(c, m):
    if not c:
        FAIL.append(m)


# ── 1. 소스에서 확인 ────────────────────────────────────────────────
tree = ast.parse(SRC)
fn = None
for n in tree.body:
    if isinstance(n, ast.FunctionDef) and n.name == "_save_models":
        fn = n
        break
ok(fn is not None, "_save_models 를 못 찾았다")
body = ast.get_source_segment(SRC, fn) if fn else ""

ok('os.replace(' in body,
   "os.replace 로 바꾸지 않는다 — 쓰다 죽으면 파일이 잘린 채 남는다")
ok('os.fsync(' in body,
   "fsync 가 없다 — 이름은 바뀌었는데 내용이 디스크에 안 앉아 있을 수 있다")
ok('.tmp' in body,
   "임시 파일을 쓰지 않는다")
ok('open(MODELS_FILE, "w"' not in body,
   "운영 파일을 아직 직접 열어서 쓴다 (open(MODELS_FILE, \"w\"))")

# 직전 사본은 그대로 있어야 한다 — '잘못 올린 엑셀 되돌리기' 용이라
# 이번 변경과 하는 일이 다르다. 같이 지워지면 안 된다.
ok('.auto_' in body, "직전 사본(.auto_*) 보관이 사라졌다")

# 순서: 임시 파일에 쓴 뒤에 replace 해야 한다
if 'os.replace(' in body and '.tmp' in body:
    ok(body.index('.tmp') < body.index('os.replace('),
       "임시 파일보다 os.replace 가 먼저 나온다 — 순서가 뒤집혔다")


# ── 2. 실제로 돌려 본다 ─────────────────────────────────────────────
#
# main.py 는 fastapi 를 import 해서 여기서 통째로 불러올 수 없다.
# 같은 방식(임시 파일 + fsync + replace)을 그대로 돌려, 중간 상태가
# 보이지 않는지만 확인한다.
with tempfile.TemporaryDirectory() as d:
    target = os.path.join(d, "models.json")
    before = {"version": 1, "projects": {"a": {"models": [1, 2, 3]}}}
    with open(target, "w", encoding="utf-8") as f:
        json.dump(before, f)

    big = {"version": 2, "projects": {str(i): {"models": list(range(200))}
                                      for i in range(300)}}
    tmp = f"{target}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(big, f, ensure_ascii=False, indent=2)
        f.flush()
        os.fsync(f.fileno())

    # 임시 파일을 다 쓴 시점에도 운영 파일은 아직 '옛날 것' 이어야 한다
    cur = json.loads(Path(target).read_text(encoding="utf-8"))
    ok(cur["version"] == 1,
       "임시 파일을 쓰는 동안 운영 파일이 벌써 바뀌었다")

    os.replace(tmp, target)
    cur = json.loads(Path(target).read_text(encoding="utf-8"))
    ok(cur["version"] == 2 and len(cur["projects"]) == 300,
       "바꾼 뒤에도 새 내용이 아니다")
    ok(not os.path.exists(tmp), "임시 파일이 남아 있다")


if FAIL:
    print("실패 %d건" % len(FAIL))
    for f in FAIL:
        print("  -", f)
    raise SystemExit(1)
print("전부 통과 · 검사 9묶음")
