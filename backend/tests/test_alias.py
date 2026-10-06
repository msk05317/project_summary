# -*- coding: utf-8 -*-
"""품번 별칭 — 같은 물건을 거래처마다 다른 품번으로 부를 때.

복사본 엑셀에는 853-800575-009 로 적혀 있고 OneView 에는
714-025898-009 로 등록돼 있다. 403 도 같다. 별칭을 안 적어 두면 올릴
때마다 못 찾은 품번이 **새 모델**로 들어와서, 같은 물건이 두 줄이 되고
보드 합계가 두 번 세어진다.

여기서 지키는 것
  · 별칭으로 적어 둔 품번이 그 모델로 붙는다
  · 파트넘버 칸도 색인에 들어간다 ('파트넘버로 찾는다' 고 적어 두고
    정작 id·모델명만 보고 있었다)
  · 색인을 넓혀도 원래 붙던 줄이 다른 모델로 안 옮겨간다
  · 별칭 라우트가 이미 등록된 품번을 남의 별칭으로 받지 않는다
"""
import ast
import collections
import re
import sys
from pathlib import Path

BACK = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACK))

import pbx_plan_import as pbx          # noqa: E402

FAIL = []


def ok(c, m):
    if not c:
        FAIL.append(m)


# ── 1. 별칭이 붙는가 ────────────────────────────────────────────────
MODELS = [
    {"id": "714-025898-009", "name": "714-025898-009", "dev_type": "009",
     "aliases": ["853-800575-009"]},
    {"id": "839-025898-403", "name": "839-025898-403", "dev_type": "413",
     "aliases": ["853-800575-403"]},
    {"id": "853-800575-413", "name": "853-800575-413", "dev_type": "413"},
    # 파트넘버가 id 와 따로인 모델
    {"id": "M-7", "name": "버스바 A", "part_number": "925-800083-394"},
]
mt = pbx.Matcher(MODELS)

for lab, want in (
    ("853-800575-009", "714-025898-009"),
    ("853-800575-403", "839-025898-403"),
    ("714-025898-009", "714-025898-009"),
    ("853-800575-413", "853-800575-413"),
    ("925-800083-394", "M-7"),            # 파트넘버 칸
    ("버스바 A", "M-7"),                   # 이름
):
    got, how = mt.match(lab)
    ok(got is not None and got.get("id") == want,
       "%s → %s (%s 여야 한다)" % (lab, (got or {}).get("id"), want))

# 엑셀 라벨은 이름과 품번이 섞여 오기도 한다
got, _h = mt.match("ENCLOSURE 853-800575-009 (구형)")
ok(got is not None and got["id"] == "714-025898-009",
   "섞인 라벨에서 별칭을 못 찾는다: %r" % ((got or {}).get("id"),))

# 별칭이 없는 품번은 그대로 못 찾아야 한다 (아무 데나 붙으면 더 나쁘다)
got, how = mt.match("111-222222-333")
ok(got is None, "모르는 품번이 %r 로 붙었다" % ((got or {}).get("id"),))


# ── 2. 색인을 넓혀도 원래 붙던 줄이 안 옮겨간다 ─────────────────────
#
# 색인에 파트넘버와 별칭을 더 넣었다. 더 넣는 건 '못 찾던 걸 찾게' 하는
# 쪽이어야 하고, '찾던 걸 다른 데로' 보내면 안 된다. 바꾸기 전 색인과
# 나란히 돌려 본다.
_s, _norm, PN_RE = pbx._s, pbx._norm, pbx.PN_RE


class OldMatcher(pbx.Matcher):
    """바꾸기 전 색인 — id·모델명만 봤다"""

    def __init__(self, models):
        self.by_id = {}
        self.by_name = collections.defaultdict(list)
        self.prefix = []
        for m in models:
            raw_id, raw_name = _s(m.get("id")), _s(m.get("name"))
            self._add_id(_norm(raw_id), m)
            for pn in PN_RE.findall(raw_id) + PN_RE.findall(raw_name):
                self._add_id(_norm(pn), m)
            for d in re.findall(r"\b\d{6,9}\b", raw_id + " " + raw_name):
                self._add_id(_norm(d), m)
            n = _norm(raw_name)
            if n:
                self.by_name[n].append(m)
        self.prefix.sort(key=lambda t: -len(t[0]))


SHAPES = [
    # 엔클로저 — id 가 곧 품번
    [{"id": "853-800575-%03d" % i, "name": "853-800575-%03d" % i,
      "dev_type": "413"} for i in (403, 404, 409, 413, 414, 426)],
    # 큐리 — 이름만 있고 품번이 없는 줄이 섞인다
    [{"id": "버스바1", "name": "버스바"}, {"id": "버스바2", "name": "버스바"},
     {"id": "P-1", "name": "플레이트", "part_number": "575-B68653-XXXX"}],
    # 파워박스 — 이름과 품번이 둘 다 있다
    [{"id": "853-B15113-313", "name": "EMA 313", "part_number": "853-B15113-313"},
     {"id": "853-B15113-314", "name": "EMA 314", "part_number": "853-B15113-314"}],
]
moved = 0
for ms in SHAPES:
    o, nw = OldMatcher(ms), pbx.Matcher(ms)
    labs = set()
    for m in ms:
        for k in ("id", "name", "part_number"):
            if _s(m.get(k)):
                labs.add(_s(m.get(k)))
    for lab in sorted(labs):
        a, _x = o.match(lab)
        b, _y = nw.match(lab)
        ai = a.get("id") if a else None
        bi = b.get("id") if b else None
        # 못 찾던 걸 찾게 되는 건 괜찮다. 찾던 게 **다른 데로** 가면 안 된다.
        if ai is not None and ai != bi:
            moved += 1
            FAIL.append("색인을 넓히자 %r 이 %s → %s 로 옮겨갔다" % (lab, ai, bi))
ok(moved == 0, "옮겨간 줄 %d개" % moved)


# ── 3. 라우트가 있는가 · 이미 등록된 품번은 막는가 ──────────────────
SRC = (BACK / "main.py").read_text(encoding="utf-8")
ok('@app.post("/admin/projects/{project_key}/models/alias")' in SRC,
   "별칭 라우트가 없다")
ok("_admin: int = Depends(get_admin_session)" in
   SRC[SRC.index("def admin_add_model_alias("):
       SRC.index("def admin_add_model_alias(") + 400],
   "별칭 라우트에 관리자 확인이 없다")
ok("이미 등록된 모델입니다" in SRC,
   "이미 등록된 품번을 남의 별칭으로 받는다 — 둘 다 그 줄로 끌려간다")

# 화면이 묶는 자리를 내주는가
AV2 = (BACK / "admin_v2.html").read_text(encoding="utf-8")
for frag, why in [
    ("pf-alias-go", "'같은 모델로 묶기' 버튼이 없다"),
    ("window._pfRerun", "묶은 뒤 미리보기를 다시 안 띄운다"),
    ("/models/alias", "화면이 별칭 라우트를 안 부른다"),
]:
    ok(frag in AV2, why)


if FAIL:
    print("실패 %d건" % len(FAIL))
    for f in FAIL:
        print("  -", f)
    raise SystemExit(1)
print("전부 통과 · 검사 3묶음 · 프로젝트 모양 %d가지" % len(SHAPES))
