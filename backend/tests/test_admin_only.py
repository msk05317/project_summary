# -*- coding: utf-8 -*-
"""admin 프로젝트 목록 — 숨긴 프로젝트 중 '자료 올리는 자리' 는 보여야 한다.

블룸은 품목 일곱 개가 각각 프로젝트인데, 올리는 파일은 품목을 전부 담고
있어서 원본이 bloom_main 한 곳에 저장된다. 그런데 bloom_main 이
visible:false 라 admin 화면에 아예 안 나왔다 — 올릴 자리가 없으니 사람들은
품목 일곱 개 중 하나를 골라 올리고 있었고, 어디서 올려도 결과가 같아서
매번 헷갈렸다.

그래서 admin_only 를 붙였다. 앱·홈이 보는 목록(visible_only=True)은 그대로
두고, admin 목록에만 끼워 넣는다. 이 둘이 어긋나면 안 되므로 여기서 묶는다.
"""
import json
import sys
from pathlib import Path

BACK = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACK))

import config_loader as cl   # noqa: E402

FAIL = []


def ok(c, m):
    if not c:
        FAIL.append(m)


MAIN = (BACK / "main.py").read_text(encoding="utf-8")


def admin_list(div):
    """main.py 의 /admin/config/projects 필터를 그대로 옮겼다."""
    items = cl.get_projects(division_id=div, visible_only=False)
    return [p for p in items if p.get("visible", True) or p.get("admin_only")]


# ── 1. 라우트가 정말 그 규칙을 쓰는가 ───────────────────────────────
for frag, why in [
    ('items = _cl.get_projects(division_id=division_id, visible_only=False)',
     "라우트가 아직 visible_only=True 다 — 숨긴 자리가 다시 사라진다"),
    ('if p.get("visible", True) or p.get("admin_only")',
     "admin_only 예외가 라우트에 없다"),
    ('"admin_only": bool(p.get("admin_only")),',
     "응답에 admin_only 가 안 들어간다"),
]:
    ok(frag in MAIN, why)


# ── 2. 블룸 — 올리는 자리가 admin 에 보인다 ─────────────────────────
ids = [p.get("id") for p in admin_list("bloom")]
ok("bloom_main" in ids, "admin 목록에 bloom_main 이 없다 — 올릴 자리가 화면에 없다")
for item in ("bloom_yfp", "bloom_corva_kpe", "bloom_sl7", "bloom_tc",
             "bloom_wdm", "bloom_bop", "bloom_bop_assy"):
    ok(item in ids, "admin 목록에서 %s 가 빠졌다" % item)
ok(len(ids) == 8, "블룸 admin 목록이 8개가 아니다: %d" % len(ids))

lead = [p for p in admin_list("bloom") if p.get("admin_only")]
ok(len(lead) == 1, "블룸의 '올리는 자리' 가 %d개다 (1개여야 한다)" % len(lead))
if lead:
    ok(lead[0].get("id") == "bloom_main", "올리는 자리가 bloom_main 이 아니다")
    ok("전체" in str(lead[0].get("label")),
       "라벨에 '전체' 가 없다 — 품목처럼 보이면 대표라는 게 안 읽힌다: %r"
       % lead[0].get("label"))


# ── 3. 앱·홈이 보는 목록은 안 바뀐다 ────────────────────────────────
vis = [p.get("id") for p in cl.get_projects(division_id="bloom", visible_only=True)]
ok("bloom_main" not in vis,
   "bloom_main 이 앱·홈 목록에도 나온다 — visible 은 false 로 둬야 한다")
ok(len(vis) == 7, "앱·홈 블룸 목록이 7개가 아니다: %d" % len(vis))


# ── 4. 다른 사업부는 하나도 안 바뀐다 ───────────────────────────────
divs = {p.get("division_id") for p in cl.get_projects(visible_only=False)
        if p.get("division_id")}
for div in sorted(divs):
    a = [p.get("id") for p in admin_list(div)]
    b = [p.get("id") for p in cl.get_projects(division_id=div, visible_only=True)]
    if div == "bloom":
        continue
    ok(a == b, "%s 의 admin 목록이 달라졌다: %s" % (div, set(a) ^ set(b)))


# ── 5. admin_only 를 아무 데나 달아 두지 않았는지 ───────────────────
alls = cl.get_projects(visible_only=False)
ao = [p.get("id") for p in alls if p.get("admin_only")]
ok(ao == ["bloom_main"], "admin_only 가 붙은 프로젝트가 예상과 다르다: %s" % ao)
for p in alls:
    if p.get("admin_only"):
        ok(p.get("visible") is False,
           "%s 는 admin_only 인데 visible 이 false 가 아니다 — 그럼 플래그가 의미 없다"
           % p.get("id"))


# ── 6. config 파일 자체가 성립하는가 ────────────────────────────────
raw = json.loads((BACK / "config" / "projects.json").read_text(encoding="utf-8"))
seen = set()
for p in raw.get("projects", []):
    i = p.get("id")
    ok(i and i not in seen, "프로젝트 id 가 비었거나 겹친다: %r" % i)
    seen.add(i)
    ok(p.get("division_id"), "%s 에 division_id 가 없다" % i)
    ok(p.get("label"), "%s 에 label 이 없다" % i)

# 화면의 '올리는 곳' 선언과 config 가 같은 곳을 가리키는가
AV2 = (BACK / "admin_v2.html").read_text(encoding="utf-8")
ok("UPLOAD_LEAD_PROJECT" in AV2, "화면에 UPLOAD_LEAD_PROJECT 선언이 없다")
ok("bloom_main: {" in AV2 or "bloom_main:{" in AV2,
   "화면의 UPLOAD_LEAD_PROJECT 가 bloom_main 을 안 가리킨다")

if FAIL:
    print("실패 %d건" % len(FAIL))
    for f in FAIL:
        print("  -", f)
    raise SystemExit(1)
print("전부 통과 · 검사 6묶음 · 사업부 %d개" % len(divs))
