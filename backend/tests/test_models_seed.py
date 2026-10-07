# -*- coding: utf-8 -*-
"""저장소에 있는 models 사본은 '데이터' 가 아니라 '씨앗' 이다.

운영은 /data/models.json 에만 쓴다. 저장소 사본은 볼륨이 비었을 때 한 번
읽히고 끝이다. 그런데 이름이 같아서 저장소 파일을 열어 보고 "데이터가 왜
두 달 전이지" 하게 됐다.

더 나쁜 건 조용한 사고다. 볼륨이 안 붙거나 비면 **에러 없이** 저장소
사본으로 떨어진다. 화면은 멀쩡하고 숫자만 몇 달 전 것이라 아무도 못
알아챈다. 그래서 여기서 지키는 건 두 가지 —

  · 저장소 사본의 이름이 models.seed.json 이다 (models.json 이 아니다)
  · 씨앗으로 떨어지면 반드시 로그에 남는다
"""
import io
import json
import os
import sys
import tempfile
from contextlib import redirect_stdout
from pathlib import Path

BACK = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACK))

FAIL = []


def ok(c, m):
    if not c:
        FAIL.append(m)


SRC = (BACK / "main.py").read_text(encoding="utf-8")


# ── 1. 이름 ─────────────────────────────────────────────────────────
ok("models.seed.json" in SRC, "씨앗 파일 이름이 코드에 없다")
ok("SEED_MODELS_FILE" in SRC, "SEED_MODELS_FILE 이 없다")
ok('"/app/models.json"' not in SRC,
   "경로가 /app 으로 박혀 있다 — 컨테이너 밖에서는 안 맞는다")
ok((BACK / "models.seed.json").exists(),
   "backend/models.seed.json 이 없다 (볼륨이 비면 떨어질 곳이 없다)")
ok(not (BACK / "models.json").exists(),
   "backend/models.json 이 아직 있다 — 둘이 같이 있으면 또 헷갈린다")


# ── 2. _load_models 를 꺼내 실제로 돌려 본다 ────────────────────────
def grab(name):
    i = SRC.index("def %s(" % name)
    rest = SRC[i:]
    cuts = [rest.index(m) for m in ("\ndef ", "\n@app.", "\n#: ", "\nclass ")
            if m in rest]
    return rest[:min(cuts)] if cuts else rest


code = grab("_load_models")
ok("global _seed_warned" in code, "씨앗 경고가 한 번만 나오게 막는 장치가 없다")


def run(models_exists, seed_exists, models_body=None, seed_body=None):
    """_load_models 를 임시 폴더에서 돌린다 → (결과, 찍힌 로그)"""
    d = Path(tempfile.mkdtemp())
    mf = d / "models.json"
    sf = d / "models.seed.json"
    if models_exists:
        mf.write_text(json.dumps(models_body), encoding="utf-8")
    if seed_exists:
        sf.write_text(json.dumps(seed_body), encoding="utf-8")
    g = {"json": json, "os": os, "Path": Path,
         "MODELS_FILE": mf, "SEED_MODELS_FILE": sf, "_seed_warned": False}
    exec(compile(code, "<load>", "exec"), g)
    buf = io.StringIO()
    with redirect_stdout(buf):
        got = g["_load_models"]()
    return got, buf.getvalue()


LIVE = {"version": 1, "projects": {"live": {"models": [1, 2, 3]}}}
SEED = {"version": 1, "projects": {"seed": {"models": [9]}}}

# 2-1. 운영 데이터가 있으면 그것만 읽는다
got, log = run(True, True, LIVE, SEED)
ok(got == LIVE, "운영 데이터가 있는데 씨앗을 읽었다: %s" % list(got.get("projects", {})))
ok("씨앗" not in log, "운영 데이터를 읽었는데 씨앗 경고가 떴다")

# 2-2. 운영 데이터가 없으면 씨앗으로 떨어지되 반드시 소리친다
got, log = run(False, True, None, SEED)
ok(got == SEED, "씨앗으로 안 떨어졌다")
ok("씨앗" in log and "볼륨" in log,
   "씨앗으로 떨어졌는데 로그가 조용하다 — 이게 원래 사고의 원인이었다:\n%r" % log)

# 2-3. 둘 다 없으면 빈 것을 돌려준다 (터지지 않는다)
got, log = run(False, False)
ok(got.get("projects") == {}, "둘 다 없을 때 빈 구조가 아니다: %r" % got)

# 2-4. 운영 데이터가 깨져 있어도 씨앗으로 이어 간다 (대신 알린다)
d = Path(tempfile.mkdtemp())
(d / "models.json").write_text("{깨진 파일", encoding="utf-8")
(d / "models.seed.json").write_text(json.dumps(SEED), encoding="utf-8")
g = {"json": json, "os": os, "Path": Path,
     "MODELS_FILE": d / "models.json", "SEED_MODELS_FILE": d / "models.seed.json",
     "_seed_warned": False}
exec(compile(code, "<load>", "exec"), g)
buf = io.StringIO()
with redirect_stdout(buf):
    got = g["_load_models"]()
ok(got == SEED, "운영 파일이 깨졌을 때 씨앗으로 안 넘어간다")
ok("읽지 못했" in buf.getvalue(), "깨진 파일을 조용히 넘겼다")


# ── 3. 쓰는 쪽은 씨앗을 건드리지 않는다 ─────────────────────────────
save = grab("_save_models")
ok("SEED_MODELS_FILE" not in save,
   "_save_models 가 씨앗을 건드린다 — 씨앗은 읽기 전용이어야 한다")
ok("MODELS_FILE" in save, "_save_models 가 운영 파일에 안 쓴다")


# ── 4. 작업 사본이 git 에 다시 들어오지 않게 ────────────────────────
GI = (BACK.parent / ".gitignore").read_text(encoding="utf-8")
for f in ("backend/models_check.json", "backend/models_trace.json",
          "backend/models.json"):
    ok(f in GI, ".gitignore 에 %s 가 없다" % f)


if FAIL:
    print("실패 %d건" % len(FAIL))
    for f in FAIL:
        print("  -", f)
    raise SystemExit(1)
print("전부 통과 · 검사 4묶음")
