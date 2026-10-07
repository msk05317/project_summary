# -*- coding: utf-8 -*-
"""작성용 양식 — 한 해 한 장, 적는 달만 펼쳐 둔다.

보고용(plan_export)과 모양이 비슷해 보여도 하는 일이 반대다. 보고용은
붙이는 것이고 이건 **다시 올라오는** 것이다. 그래서 여기서 지키는 건
거의 다 '올렸을 때 제대로 읽히는가' 다.

  · 열두 달 주차가 다 들어 있고, 적는 달만 펼쳐져 있다
  · 접힌 달도 펴서 적으면 올라간다 (접은 것뿐, 지운 게 아니다)
  · 중간에 '합계' 줄이 없다 — 읽는 쪽이 거기서 표가 끝난 줄 안다
  · 0 은 빈 칸이다 — '아직 안 정함' 과 '정말 0' 이 구분돼야 한다
  · 적는 달은 칠하지 않고 테두리로 표시한다 (빨강 = '못 미쳤다' 라서)
"""
import sys
from io import BytesIO
from pathlib import Path

BACK = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACK))

from openpyxl import load_workbook          # noqa: E402

import pbx_plan_import as pbx               # noqa: E402
import plan_form as pf                      # noqa: E402
import week_calendar as wcal                # noqa: E402

FAIL = []


def ok(c, m):
    if not c:
        FAIL.append(m)


YEAR = 2026
MON = "2026-10"
W10 = wcal.get_month_weeks(MON)
W9 = wcal.get_month_weeks("2026-09")
W8 = wcal.get_month_weeks("2026-08")

MODELS = [
    {"id": "A-413", "name": "A-413", "dev_type": "413", "group": "양산",
     "price": 2931.15, "material_cost": 1204, "po_qty": 3226, "shipped_qty": 2670,
     "weekly_plan": {
         MON: {W10[0]: {"plan": 82, "actual": 0},
               W10[2]: {"plan": 123, "actual": 5}},
         "2026-09": {W9[0]: {"plan": 200, "actual": 180},
                     W9[1]: {"plan": 238, "actual": 265}},
         "2026-08": {W8[0]: {"plan": 0, "actual": 0}},
     }},
    {"id": "B-009", "name": "B-009", "dev_type": "009", "group": "양산",
     "po_qty": 1117, "shipped_qty": 1117},
    {"id": "C-301", "name": "C-301", "dev_type": "009", "group": "개발"},
]

NOTES = {MON: {W10[0]: "자재 입고 지연"}, "2026-09": {W9[1]: "설비 점검"}}
data = pf.build_year_form("엔클로저", YEAR, MON, MODELS, notes=NOTES)
wb = load_workbook(BytesIO(data))


# ── 1. 시트 ─────────────────────────────────────────────────────────
ok(MON in wb.sheetnames, "시트 이름이 그 달이 아니다: %s" % wb.sheetnames)
ok("작성 안내" in wb.sheetnames, "작성 안내 시트가 없다")
ws = wb[MON]


# ── 2. 열두 달 주차가 다 있다 ───────────────────────────────────────
tops, weeks_seen = {}, []
for c in range(1, ws.max_column + 1):
    v = str(ws.cell(pf.HDR_TOP, c).value or "")
    if "월" in v and v.split("월")[0].strip().isdigit():
        tops[int(v.split("월")[0].strip())] = c
    w = str(ws.cell(pf.HDR_WEEK, c).value or "").upper()
    if w.startswith("W") and w[1:].isdigit():
        weeks_seen.append(w)
ok(sorted(tops) == list(range(1, 13)), "열두 달이 다 있어야 한다: %s" % sorted(tops))

want = []
for i in range(1, 13):
    want += list(wcal.get_month_weeks("%d-%02d" % (YEAR, i)))
ok(weeks_seen == want,
   "열두 달 주차가 다 있어야 한다 (접는 것이지 빼는 게 아니다)\n  나온 것 %d개\n"
   "  있어야 할 것 %d개" % (len(weeks_seen), len(want)))
ok(any(w in weeks_seen for w in wcal.get_month_weeks("2026-06")), "6월 주차가 없다")

n_tot = sum(1 for c in range(1, ws.max_column + 1)
            if str(ws.cell(pf.HDR_WEEK, c).value or "") == "월 합계")
ok(n_tot == 12, "월 합계가 달마다 하나씩 있어야 한다: %d개" % n_tot)


# ── 3. 접힘 — 적는 달만 펼쳐져 있다 ─────────────────────────────────
from openpyxl.utils import get_column_letter as _L      # noqa: E402

blocks = {int(b["month"][5:7]): b for b in pf.layout(YEAR, MON)}
c = None
hidden, shown = [], []
for mi, b in sorted(blocks.items()):
    col = _L(tops[mi])
    d = ws.column_dimensions.get(col)
    (hidden if (d is not None and d.hidden) else shown).append(mi)
ok(shown == [10], "펼쳐진 달이 10월 하나여야 한다: 펼침 %s · 접힘 %s" % (shown, hidden))
# 월 합계 두 칸은 접힌 달도 보여야 한다
c9 = tops[9]
while str(ws.cell(pf.HDR_WEEK, c9).value or "") != "월 합계":
    c9 += 1
d9 = ws.column_dimensions.get(_L(c9))
ok(d9 is None or not d9.hidden, "접힌 달의 월 합계까지 숨으면 그 달이 안 보인다")


# ── 4. 줄 ───────────────────────────────────────────────────────────
rows, r_sum = {}, None
for r in range(pf.FIRST_ROW, ws.max_row + 1):
    nm = str(ws.cell(r, 1).value or "").strip()
    if nm == "합계":
        r_sum = r
        break
    if nm:
        rows[nm] = r
ok(set(rows) == {"A-413", "B-009", "C-301"}, "모델 줄이 다 안 나왔다: %s" % list(rows))
ok(r_sum is not None, "합계 줄이 없다")
labels = [str(ws.cell(r, 1).value or "").strip()
          for r in range(pf.FIRST_ROW, ws.max_row + 1)]
ok(labels.count("합계") == 1,
   "'합계' 줄이 하나여야 한다 (묶음 합계를 두면 읽기가 거기서 끊긴다): %d개"
   % labels.count("합계"))


# ── 5. 값 ───────────────────────────────────────────────────────────
r413 = rows["A-413"]
c10 = tops[10]
ok(ws.cell(r413, c10).value == 82, "적는 달 계획이 안 들어갔다: %r"
   % ws.cell(r413, c10).value)
ok(ws.cell(r413, c10 + 1).value is None,
   "0 은 빈 칸이어야 한다 ('아직 안 정함' 과 구분): %r" % ws.cell(r413, c10 + 1).value)
# 접힌 달도 숫자가 들어 있어야 한다 — 펴서 보려는 것이니까
c9w = tops[9]
ok(ws.cell(r413, c9w).value == 200,
   "접힌 달 주차가 비었다 — 접은 것이지 빼는 게 아니다: %r" % ws.cell(r413, c9w).value)
ok(ws.cell(r413, c9w + 2).value == 238, "접힌 달 둘째 주가 비었다")

# 월 합계는 그 달 주차를 더하는 수식
f9 = ws.cell(r413, c9).value
ok(isinstance(f9, str) and f9.startswith("=") and "COUNT(" in f9,
   "월 합계가 수식이 아니다: %r" % f9)

heads = {str(ws.cell(pf.HDR_TOP, c).value or ""): c for c in range(1, 12)}
for h, v in (("판가($)", 2931.15), ("PO수량", 3226), ("실적수량", 2670)):
    ok(ws.cell(r413, heads[h]).value == v,
       "%s 가 안 채워졌다: %r" % (h, ws.cell(r413, heads[h]).value))


# ── 6. 적는 달은 칠하지 않고 테두리로 ───────────────────────────────
#
# 보드에서 빨강은 '계획에 못 미쳤다' 다. 칸을 칠하면 '여기가 문제' 로 읽힌다.
def red(side):
    return (side.style in ("medium", "thick") and side.color is not None
            and (side.color.rgb or "")[-6:].upper() == pf.RED)


hd = ws.cell(pf.HDR_WEEK, c10)
ok((hd.fill.fgColor.rgb or "")[-6:].upper() != pf.RED,
   "적는 달 머리글을 빨갛게 칠했다 — 테두리로만 표시해야 한다")
# 테두리는 블록 바깥쪽에만 — 위는 월 이름 줄, 왼쪽은 첫 주차 열
ok(red(ws.cell(pf.HDR_TOP, c10).border.top), "적는 달 위쪽에 빨간 테두리가 없다")
ok(red(ws.cell(r413, c10).border.left), "적는 달 왼쪽에 빨간 테두리가 없다")
c10e = tops[11] - 1          # 11월 바로 앞 = 10월 블록 마지막 열
ok(red(ws.cell(r413, c10e).border.right), "적는 달 오른쪽에 빨간 테두리가 없다")
ok(not red(ws.cell(r413, c10 + 1).border.left),
   "안쪽 줄까지 빨개졌다 — 바깥 테두리만이어야 한다")
# 접힌 달에는 빨간 테두리가 없어야 한다
l9 = ws.cell(r413, c9w).border.left
ok(not (l9.color and (l9.color.rgb or "")[-6:].upper() == pf.RED),
   "접힌 달에도 빨간 테두리가 갔다")


# ── 7. 되읽기 — 열두 달이 다 올라가는가 ─────────────────────────────
#
# 시트 하나를 달 하나로만 읽으면, 펴서 적은 9월이 조용히 사라진다.
ok(pbx.sheet_months_of(ws) == ["%d-%02d" % (YEAR, i) for i in range(1, 13)],
   "한 해짜리 시트로 안 보인다: %s" % pbx.sheet_months_of(ws))

got = {g["month"]: g for g in pbx.sheet_months(wb)}
ok(MON in got, "적는 달이 안 읽힌다: %s" % list(got))
ok("2026-09" in got, "접힌 달이 안 읽힌다 — 펴서 적어도 사라진다: %s" % list(got))
ok("2026-11" not in got, "숫자가 없는 달까지 읽힌다: %s" % list(got))

p10 = pbx.parse_sheet(ws, month=MON)
by = {r["label"]: r["weeks"] for r in p10["rows"]}
ok("A-413" in by, "적는 달 줄을 못 읽었다")
if "A-413" in by:
    w = by["A-413"]
    ok((w[W10[0]]["plan"], w[W10[0]]["actual"]) == (82, 0),
       "되읽은 값이 다르다: %r" % w[W10[0]])
    ok((w[W10[2]]["plan"], w[W10[2]]["actual"]) == (123, 5),
       "되읽은 값이 다르다: %r" % w[W10[2]])
ok("B-009" not in by,
   "빈 줄이 읽혔다 — 올리면 그 달이 통째로 0 이 된다")

p9 = pbx.parse_sheet(ws, month="2026-09")
w9 = {r["label"]: r["weeks"] for r in p9["rows"]}.get("A-413") or {}
ok((w9.get(W9[0]) or {}).get("plan") == 200,
   "접힌 달을 되읽으면 값이 다르다: %r" % w9.get(W9[0]))


# ── 8. 미달 사유도 달마다 ───────────────────────────────────────────
ok(p10.get("week_notes", {}).get(W10[0]) == "자재 입고 지연",
   "적는 달 미달 사유가 안 읽힌다: %r" % p10.get("week_notes"))
ok(p9.get("week_notes", {}).get(W9[1]) == "설비 점검",
   "접힌 달 미달 사유가 안 읽힌다: %r" % p9.get("week_notes"))


# ── 9. 남의 파일은 그대로 읽는다 ────────────────────────────────────
#
# 'YYYY-MM' 이름에 그 달 주차만 든 시트(예전 양식)는 한 달로 읽어야 한다.
import weekly_template as wt                # noqa: E402

old = wt.build_weekly_template("엔클로저",
                               sheets=[{"month": MON, "weeks": list(W10)}],
                               models=MODELS, filled=True)
ws_old = load_workbook(BytesIO(old))[MON]
ok(pbx.sheet_months_of(ws_old) == [],
   "예전 양식까지 한 해로 본다 — 남의 파일을 건드리면 안 된다")


# ── 10. 라우트 · 화면 ───────────────────────────────────────────────
SRC = (BACK / "main.py").read_text(encoding="utf-8")
ok('@app.get("/admin/projects/{project_key}/plan-form")' in SRC, "라우트가 없다")
_b = SRC[SRC.index("def admin_plan_form("):]
_b = _b[:_b.index("\n@app.")] if "\n@app." in _b else _b
ok("get_admin_session" in _b, "라우트에 관리자 확인이 없다")
ok("build_year_form" in _b, "라우트가 작성용을 안 만든다")

AV2 = (BACK / "admin_v2.html").read_text(encoding="utf-8")
ok("'/plan-form'" in AV2, "화면이 작성용을 안 부른다")
ok("_dlItem('form'" in AV2 and "_dlItem('report'" in AV2,
   "받기 메뉴에 작성용·보고용이 다 있어야 한다")
ok("wp-year" not in AV2, "없어진 연간 버튼을 아직 찾고 있다")


# ── 11. 안 되는 달 ──────────────────────────────────────────────────
for bad, why in (("2025-10", "다른 해를 골랐는데 안 막는다"),
                 ("2026-13", "없는 달을 안 막는다")):
    try:
        pf.build_year_form("x", YEAR, bad, MODELS)
        FAIL.append(why)
    except Exception:
        pass


if FAIL:
    print("실패 %d건" % len(FAIL))
    for x in FAIL:
        print("  -", x)
    raise SystemExit(1)
print("전부 통과 · 검사 11묶음 · 달 12개 · 주차 %d개" % len(weeks_seen))
