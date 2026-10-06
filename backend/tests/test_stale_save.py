# -*- coding: utf-8 -*-
"""모델 목록 저장이 엑셀로 들어온 값을 되돌리지 않는가.

실제로 났던 일 —
  1. 엑셀을 올려 714-025898-009 의 PO 가 1,117 이 됐다
  2. 열어 둔 모델 목록에서 **다른 줄** 하나를 지우고 저장했다
  3. PO 가 0 으로 돌아갔다

저장은 화면이 들고 있던 목록을 통째로 보낸다. 그 사본은 화면을 열 때
받은 것이라 엑셀이 넣은 값을 모른다. 그래서 화면이 **열 때 받은 값
(base)** 도 같이 보내고, 서버가 이렇게 가른다.

  보낸 값 == base  → 사람이 안 건드린 칸 → 서버 값을 쓴다
  보낸 값 != base  → 사람이 고친 칸      → 보낸 값을 쓴다

여기서 지키는 것
  · 안 건드린 칸은 그 사이 들어온 값이 남는다
  · 사람이 고친 칸은 그대로 들어간다 (고치는 걸 막으면 안 된다)
  · base 를 안 보내면 예전처럼 보낸 값을 다 쓴다 (옛 화면 호환)
  · 쉼표가 붙은 '1,117' 과 숫자 1117 을 같은 값으로 본다
  · 안 건드린 판가는 판가 '구간' 도 안 만든다
"""
import ast
import sys
from pathlib import Path

BACK = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACK))

FAIL = []


def ok(c, m):
    if not c:
        FAIL.append(m)


SRC = (BACK / "main.py").read_text(encoding="utf-8")


def _grab(name):
    """main.py 에서 함수 하나만 떼어 온다 (fastapi 없이 돌리려고).

    다음 'def' 만 보면 그 앞의 @app.put 데코레이터까지 딸려 와서 깨진다.
    함수 다음에 오는 것 중 제일 먼저 나오는 자리에서 자른다.
    """
    i = SRC.index("def %s(" % name)
    ends = [SRC.find(m, i + 1) for m in ("\ndef ", "\n@app.", "\n#: ", "\nclass ")]
    j = min([e for e in ends if e > 0])
    return SRC[i:j]


NS = {}
exec("_SAVE_GUARDED = %s" % SRC.split("_SAVE_GUARDED = ")[1].split("\n")[0], NS)
for _n in ("_as_money", "_as_int", "_save_untouched"):
    exec(_grab(_n), NS)

untouched = NS["_save_untouched"]
GUARDED = NS["_SAVE_GUARDED"]


# ── 1. 네 칸을 지키는가 ─────────────────────────────────────────────
ok(set(GUARDED) == {"price", "material_cost", "po_qty", "shipped_qty"},
   "지키는 칸이 다르다: %r" % (GUARDED,))


# ── 2. 같다/다르다 판단 ─────────────────────────────────────────────
ok(untouched("po_qty", 0, 0), "0 과 0 을 다르다고 본다")
ok(untouched("po_qty", "1,117", 1117), "쉼표 붙은 숫자를 다르다고 본다")
ok(untouched("po_qty", 1117, "1117"), "글자와 숫자를 다르다고 본다")
ok(untouched("price", 9100.0, 9100), "소수점 표기를 다르다고 본다")
ok(untouched("po_qty", None, 0), "빈 값과 0 을 다르다고 본다")
ok(not untouched("po_qty", 1117, 0), "1117 과 0 을 같다고 본다")
ok(not untouched("price", 9100, 9500), "다른 판가를 같다고 본다")
ok(untouched("note", " 메모 ", "메모"), "앞뒤 공백을 다르다고 본다")


# ── 3. 라우트가 실제로 쓰는가 ───────────────────────────────────────
for frag, why in [
    ('base_map = payload.get("base")', "저장이 base 를 안 받는다"),
    ("_b = base_map.get(mid)", "저장이 base 를 안 본다"),
    ("entry[_f] = old[_f]", "안 건드린 칸을 서버 값으로 안 되돌린다"),
]:
    ok(frag in SRC, why)

# 되돌리는 자리가 _apply_price_change **앞** 이어야 한다.
# 뒤로 가면 판가를 되돌려도 '바뀐 것' 으로 읽혀서 쓸데없는 구간이 생긴다.
ok(SRC.index("_b = base_map.get(mid)") < SRC.index("_chg = _apply_price_change("),
   "되돌리기가 판가 구간 기록보다 뒤에 있다")

# weekly_plan 보존은 그대로 있어야 한다 (예전에 같은 사고로 넣은 것)
ok('for _keep in ("weekly_plan"' in SRC, "weekly_plan 보존이 사라졌다")


# ── 4. 화면이 base 를 만들고 보내는가 ───────────────────────────────
AV2 = (BACK / "admin_v2.html").read_text(encoding="utf-8")
for frag, why in [
    ("window._mdlSnapBase = function", "화면이 base 를 안 만든다"),
    ("base: window._modelsBase || {}", "저장할 때 base 를 안 보낸다"),
    ("window._mdlSnapBase(window._modelsData, true)", "목록을 받을 때 base 를 안 찍는다"),
    ("window._mdlSnapBase(fresh, true)", "다시 받을 때 base 를 안 찍는다"),
]:
    ok(frag in AV2, why)

# base 는 **서버에서 받은 직후** 에만 찍어야 한다. 표를 다시 그릴 때나
# 사람이 칸을 칠 때 찍으면, 방금 친 값이 '원래 값' 이 되어 영영 저장되지
# 않는다. 그래서 찍는 자리가 세 군데뿐인지, 그 세 군데가 모두 서버에서
# 막 받아 온 목록 옆인지를 본다.
_calls = [i for i in range(len(AV2))
          if AV2.startswith("_mdlSnapBase(", i)
          and not AV2.startswith("_mdlSnapBase = ", i)]
ok(len(_calls) == 3, "base 를 찍는 자리가 %d곳이다 (3곳이어야 한다)" % len(_calls))
for _i in _calls:
    _near = AV2[max(0, _i - 400):_i]
    ok("d.models" in _near or "fresh" in _near,
       "서버에서 막 받은 자리가 아닌 곳에서 base 를 찍는다:\n    ...%s"
       % AV2[max(0, _i - 90):_i + 40].replace("\n", " "))

# 표를 그리는 함수 안에서는 절대 찍지 않는다 (중괄호를 세어 끝을 찾는다)
_i = AV2.index("window.renderTable = function renderTable(")
_d, _j = 0, AV2.index("{", _i)
_k = _j
while True:
    c = AV2[_k]
    if c == "{":
        _d += 1
    elif c == "}":
        _d -= 1
        if _d == 0:
            break
    _k += 1
ok("_mdlSnapBase" not in AV2[_i:_k],
   "표를 그릴 때 base 를 찍는다 — 사람이 친 값이 저장되지 않는다")


# ── 5. 실제로 되돌아가는가 (라우트 몸통을 흉내 낸다) ────────────────
#
# 라우트 전체는 fastapi 가 있어야 돌아서, 지키는 부분만 똑같이 따라 한다.
def save(old, sent, base):
    """저장 한 줄 → 들어갈 값"""
    entry = dict(old)
    entry.update({f: sent.get(f) for f in GUARDED})
    if isinstance(base, dict):
        for f in GUARDED:
            if f not in base or f not in old:
                continue
            if untouched(f, sent.get(f), base.get(f)):
                entry[f] = old[f]
    return entry


# 화면을 열 때는 PO 가 비어 있었다 → 그 사이 엑셀이 1,117 을 넣었다
BASE = {"price": 2931.15, "material_cost": 468.15, "po_qty": 0, "shipped_qty": 0}
NOW = {"price": 2931.15, "material_cost": 468.15, "po_qty": 1117, "shipped_qty": 1117}

# (가) 사람은 아무것도 안 건드리고 다른 줄만 지우고 저장했다
got = save(NOW, dict(BASE), BASE)
ok(got["po_qty"] == 1117 and got["shipped_qty"] == 1117,
   "안 건드렸는데 엑셀이 넣은 PO 가 되돌아갔다: %r" % got)

# (나) 사람이 판가를 고쳤다 → 그건 들어가야 한다
sent = dict(BASE); sent["price"] = 3100
got = save(NOW, sent, BASE)
ok(got["price"] == 3100, "사람이 고친 판가가 안 들어갔다: %r" % got["price"])
ok(got["po_qty"] == 1117, "같은 줄의 안 건드린 칸이 되돌아갔다: %r" % got)

# (다) 사람이 PO 를 0 으로 비웠다 → 비우는 것도 고친 것이다
sent = dict(NOW); sent["po_qty"] = 0
got = save(NOW, sent, NOW)
ok(got["po_qty"] == 0, "사람이 비운 PO 가 안 들어갔다: %r" % got["po_qty"])

# (라) base 를 안 보내면 예전처럼 보낸 값을 다 쓴다
got = save(NOW, dict(BASE), None)
ok(got["po_qty"] == 0, "base 없이도 서버 값을 지켰다 (옛 화면 호환이 깨진다): %r" % got)

# (마) 새 모델은 old 에 그 칸이 없다 → 보낸 값이 들어간다
got = save({}, {"price": 100, "material_cost": 40, "po_qty": 5, "shipped_qty": 0},
           {"price": 100, "material_cost": 40, "po_qty": 5, "shipped_qty": 0})
ok(got["po_qty"] == 5, "새 모델 값이 안 들어간다: %r" % got)


if FAIL:
    print("실패 %d건" % len(FAIL))
    for f in FAIL:
        print("  -", f)
    raise SystemExit(1)
print("전부 통과 · 검사 5묶음")
