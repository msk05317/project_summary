# -*- coding: utf-8 -*-
"""주차별 계획 — 양식과 파서를 묶는다.

양식(weekly_template)을 받아 채워 올리면 파서(pbx_plan_import)가 읽는다.
둘은 서로 모르는 파일이라 한쪽만 고치면 조용히 어긋난다. 머리글 한 글자,
칸 하나만 움직여도 '못 읽음' 이 되고, 화면에는 아무 일도 안 일어난 것처럼
보인다. 그래서 여기서 **양식을 만들어 채우고 다시 읽는다**.

특히 보는 것
  · 머리글 두 줄(W## / 계획·실적)을 파서가 그대로 찾는가
  · '월 합계' 칸을 주차로 착각하지 않는가
  · 왼쪽 칸이 빠진 양식(파트넘버·유형 없는 프로젝트)도 읽는가
  · 적어 넣은 숫자가 그 모델, 그 주차로 돌아오는가
  · 한 파일에 여러 달이 있을 때 고른 달만 읽는가
"""
import sys
from io import BytesIO
from pathlib import Path

BACK = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACK))

from openpyxl import load_workbook          # noqa: E402

import pbx_plan_import as pbx               # noqa: E402
import week_calendar as wcal                # noqa: E402
import weekly_template as wt                # noqa: E402

FAIL = []


def ok(c, m):
    if not c:
        FAIL.append(m)


def mk(n, dev_type=True, part=True, prefix="M"):
    out = []
    for i in range(n):
        m = {"id": "%s-%04d" % (prefix, i), "name": "%s-%04d" % (prefix, i),
             "group": "개발" if i % 4 == 0 else "양산"}
        if dev_type:
            m["dev_type"] = ["413", "009", "EMA"][i % 3]
        if part:
            m["part_number"] = "PN-%s-%04d" % (prefix, i)
        out.append(m)
    return out


def sheets_for(months):
    return [{"month": m, "weeks": wcal.get_month_weeks(m)} for m in months]


def build(models, months=("2026-10",)):
    return wt.build_weekly_template("T", sheets=sheets_for(list(months)),
                                    models=models)


def n_fixed(ws):
    """왼쪽 고정 칸 수 — 프로젝트마다 다르다 (안 쓰는 칸은 빠진다)."""
    c = 0
    while c < 14:
        v = ws.cell(wt.HDR_TOP, c + 1).value
        t = "" if v is None else str(v).strip()
        if not t or t == "월 합계" or t.upper().startswith("W"):
            break
        c += 1
    return c


def fill(models, cells, months=("2026-10",)):
    """양식을 만들어 숫자를 적어 넣고 다시 연다.

    cells = [(줄 번호(0부터), 주차 index, 계획, 실적)]
    """
    wb = load_workbook(BytesIO(build(models, months)))
    ws = wb[months[0]]
    nf = n_fixed(ws)
    for i, wi, p, a in cells:
        c = nf + wi * wt.WEEK_N + 1
        if p is not None:
            ws.cell(wt.FIRST_ROW + i, c, p)
        if a is not None:
            ws.cell(wt.FIRST_ROW + i, c + 1, a)
    buf = BytesIO()
    wb.save(buf)
    return load_workbook(BytesIO(buf.getvalue()), data_only=True)


# ── 1. 프로젝트 모양이 어떻든 읽힌다 ────────────────────────────────
SHAPES = {
    "둘 다 있음 (프레임 형)": mk(6, dev_type=True, part=True),
    "품번 없음 (엔클로저·큐리 형)": mk(6, dev_type=True, part=False),
    "유형 없음": mk(6, dev_type=False, part=True),
    "둘 다 없음 (챔버 형)": mk(6, dev_type=False, part=False),
    "많은 것 (파워박스 형)": mk(82, dev_type=True, part=False),
}
for label, ms in SHAPES.items():
    wb = fill(ms, [(0, 0, 10, 8), (1, 1, 20, 20), (2, 3, 7, None)])
    got = pbx.parse(wb)
    if not got:
        FAIL.append("%s · 파서가 양식을 못 읽는다" % label)
        continue
    ok(got["month"] == "2026-10", "%s · 달을 %r 로 봤다" % (label, got["month"]))
    ok(got["weeks"] == wcal.get_month_weeks("2026-10"),
       "%s · 주차가 달력과 다르다: %s" % (label, got["weeks"]))
    ok(len(got["rows"]) == 3,
       "%s · 숫자 적은 줄 3개만 와야 하는데 %d개" % (label, len(got["rows"])))

    by = {r["label"]: r["weeks"] for r in got["rows"]}
    names = [r["label"] for r in got["rows"]]
    w = got["weeks"]
    ok(by.get(names[0], {}).get(w[0]) == {"plan": 10, "actual": 8},
       "%s · 첫 줄 W41 이 10/8 이 아니다: %r" % (label, by.get(names[0], {}).get(w[0])))
    ok(by.get(names[1], {}).get(w[1]) == {"plan": 20, "actual": 20},
       "%s · 둘째 줄 W42 가 20/20 이 아니다" % label)
    ok(by.get(names[2], {}).get(w[3]) == {"plan": 7, "actual": 0},
       "%s · 셋째 줄 W44 계획만 적은 것이 안 들어왔다" % label)

    # 적은 줄이 등록된 모델로 돌아오는가
    M = pbx.Matcher(ms)
    miss = [n for n in names if not M.match(n)]
    ok(not miss, "%s · 모델을 못 찾는 줄: %s" % (label, miss))


# ── 1-2. 모델 한 종짜리 — 빈 줄에 적은 숫자는 버린다 ───────────────
#
# 양식에는 새 모델 적을 빈 줄이 딸려 있다. 거기에 모델명 없이 숫자만
# 적으면 어느 모델 것인지 알 수 없다. 조용히 아무 모델에나 붙이면 안 된다.
one = mk(1, dev_type=False, part=False)
g1 = pbx.parse(fill(one, [(0, 0, 10, 8), (3, 0, 99, 99)]))
ok(g1 and len(g1["rows"]) == 1,
   "모델명 없는 줄의 숫자까지 읽었다: %s"
   % [r["label"] for r in (g1 or {}).get("rows") or []])
if g1:
    ok(g1["rows"][0]["weeks"][g1["weeks"][0]] == {"plan": 10, "actual": 8},
       "한 종짜리에서 숫자가 안 돌아온다: %r" % g1["rows"][0]["weeks"])


# ── 2. '월 합계' 를 주차로 착각하지 않는다 ──────────────────────────
ms = mk(4, dev_type=True, part=False)
wb = load_workbook(BytesIO(build(ms)))
ws = wb["2026-10"]
nf = n_fixed(ws)
sum_c = nf + len(wcal.get_month_weeks("2026-10")) * wt.WEEK_N + 1
ok(str(ws.cell(wt.HDR_TOP, sum_c).value or "").strip() == "월 합계",
   "'월 합계' 자리가 바뀌었다 — 이 검사의 전제가 깨졌다")
got = pbx.parse(fill(ms, [(0, 0, 11, 11)]))
ok(got and len(got["weeks"]) == 4,
   "주차가 4개가 아니다 — '월 합계' 를 주차로 셌다: %s" % (got or {}).get("weeks"))


# ── 3. 빈 줄은 안 들어온다 ──────────────────────────────────────────
#
# 양식에는 새 모델 적을 빈 줄이 열두 개 딸려 있다. 그게 0 으로 들어오면
# 멀쩡하던 계획이 전부 0 이 된다.
got = pbx.parse(fill(mk(5, dev_type=False, part=False), [(0, 0, 9, 9)]))
ok(got and len(got["rows"]) == 1,
   "빈 줄까지 읽었다: %d 줄" % len((got or {}).get("rows") or []))


# ── 4. 한 파일에 여러 달 ────────────────────────────────────────────
ms = mk(3, dev_type=True, part=False)
raw = build(ms, months=("2026-10", "2026-11"))
wb = load_workbook(BytesIO(raw))
for mon, val in (("2026-10", 100), ("2026-11", 200)):
    ws = wb[mon]
    ws.cell(wt.FIRST_ROW, n_fixed(ws) + 1, val)
buf = BytesIO()
wb.save(buf)
two = load_workbook(BytesIO(buf.getvalue()), data_only=True)

for mon, want in (("2026-10", 100), ("2026-11", 200)):
    g = pbx.parse(two, month=mon)
    ok(g is not None, "%s 시트를 못 읽는다" % mon)
    if g:
        ok(g["month"] == mon, "%s 를 달라고 했는데 %s 를 줬다" % (mon, g["month"]))
        first = g["rows"][0]["weeks"][g["weeks"][0]]
        ok(first["plan"] == want,
           "%s 첫 주차 계획이 %r 이다 (%d 여야 한다) — 달이 섞였다"
           % (mon, first["plan"], want))

seen = {s["month"] for s in pbx.sheet_months(two)}
ok(seen == {"2026-10", "2026-11"}, "달 목록이 다르다: %s" % seen)

# '작성 안내' 시트는 자료로 세지 않는다
ok(all(s["sheet"] != "작성 안내" for s in pbx.sheet_months(two)),
   "'작성 안내' 시트를 자료로 읽었다")


# ── 5. 달력은 한 군데서만 ───────────────────────────────────────────
#
# 양식의 주차와 파서가 되돌려주는 주차가 다르면 올려도 칸이 안 맞는다.
for mon in ("2026-01", "2026-09", "2026-10", "2026-12", "2027-03"):
    wks = wcal.get_month_weeks(mon)
    wb = load_workbook(BytesIO(build(mk(2, part=False), months=(mon,))))
    ws = wb[mon]
    ws.cell(wt.FIRST_ROW, n_fixed(ws) + 1, 5)
    buf = BytesIO()
    wb.save(buf)
    g = pbx.parse(load_workbook(BytesIO(buf.getvalue()), data_only=True))
    ok(g and g["weeks"] == wks,
       "%s · 양식 주차 %s 가 달력 %s 와 다르다" % (mon, (g or {}).get("weeks"), wks))
    ok(g and g["month"] == mon, "%s · 파서가 달을 %r 로 봤다" % (mon, (g or {}).get("month")))


# ── 5-2. 표가 아래쪽에 있고 두 달에 걸친 경우 (하바 현황 파일 모양) ──
#
# 하바플레이트 현황 엑셀은 한 시트가 한 주차의 스냅샷이고, 주차표는 그
# 시트 **맨 아래**(84행쯤)에 붙어 있다. 게다가 W40~W44 라 달력으로는
# 9월(W40)과 10월(W41~44)에 걸친다.
#
# 예전에는 둘 다 못 읽었다 — 파서가 위에서 30줄까지만 훑었고, 읽었더라도
# '이 시트의 대표 달' 하나만 정해서 9월이 통째로 버려졌다.
from openpyxl import Workbook                  # noqa: E402

wbh = Workbook()
wsh = wbh.active
wsh.title = "W40"
wsh.cell(1, 2, "1. 현황")
wsh.cell(2, 2, "하바플레이트")
wsh.cell(11, 3, "모델")
for i in range(12, 30):                        # 위쪽 섹션들 (주차표가 아니다)
    wsh.cell(i, 3, "713-00%04d-001" % i)
    wsh.cell(i, 7, i)
R = 84                                         # 주차 머리글이 84행
for j, w in enumerate(("W40", "W41", "W42", "W43", "W44")):
    wsh.cell(R, 17 + j * 2, w)
wsh.cell(R - 1, 3, "파트번호")
for j in range(5):
    wsh.cell(R + 1, 17 + j * 2, "계획")
    wsh.cell(R + 1, 18 + j * 2, "실적")
PARTS = ["713-312133-006", "839-B74773-001", "713-B62356-002"]
for i, pn in enumerate(PARTS):
    r = R + 2 + i
    wsh.cell(r, 3, pn)
wsh.cell(R + 2, 17, 4)      # W40 계획
wsh.cell(R + 2, 18, 4)      # W40 실적
wsh.cell(R + 2, 19, 2)      # W41 계획
wsh.cell(R + 3, 21, 9)      # 둘째 줄 W42 계획
wsh.cell(R + 3, 23, 10)     # 둘째 줄 W43 계획
wsh.cell(R + 5, 3, "total")  # 여기서 끊어야 한다

ok(pbx._find_week_header(wsh) is not None,
   "84행에 있는 주차 머리글을 못 찾는다 — 위에서 30줄만 훑고 있다")

allm = pbx.parse_sheet_all(wsh)
by = {g["month"]: g for g in allm}
ok(sorted(by) == ["2026-09", "2026-10"],
   "두 달로 안 갈렸다: %s — W40 은 9월, W41~44 는 10월이다" % sorted(by))
if "2026-09" in by:
    g9 = by["2026-09"]
    ok(g9["weeks"] == ["W40"], "9월 쪽 주차가 W40 하나가 아니다: %s" % g9["weeks"])
    ok(len(g9["rows"]) == 1, "9월 쪽 줄이 1개가 아니다: %d" % len(g9["rows"]))
    ok(g9["rows"][0]["weeks"]["W40"] == {"plan": 4, "actual": 4},
       "9월 W40 이 4/4 가 아니다: %r" % g9["rows"][0]["weeks"]["W40"])
if "2026-10" in by:
    g10 = by["2026-10"]
    ok(g10["weeks"] == ["W41", "W42", "W43", "W44"],
       "10월 쪽 주차가 다르다: %s" % g10["weeks"])
    labs = [r["label"] for r in g10["rows"]]
    ok(labs == PARTS[:2], "10월 쪽 줄이 %s — total 에서 안 끊겼거나 빈 줄이 섞였다" % labs)

# 같은 달 시트가 여럿이면 가장 알찬(최신) 것
wb2 = Workbook()
for idx, (name, nrows) in enumerate((("W39", 1), ("W40", 3))):
    w = wb2.active if idx == 0 else wb2.create_sheet()
    w.title = name
    w.cell(2, 1, "모델")
    for j, wk in enumerate(("W41", "W42")):
        w.cell(2, 3 + j * 2, wk)
    for j in range(2):
        w.cell(3, 3 + j * 2, "계획")
        w.cell(3, 4 + j * 2, "실적")
    for i in range(nrows):
        w.cell(4 + i, 1, "PN-%04d" % i)
        w.cell(4 + i, 3, 10 + i)
g = pbx.parse(wb2, month="2026-10")
ok(g and g["sheet"] == "W40",
   "같은 달 시트가 둘일 때 오래된 쪽(%s)을 집었다" % (g or {}).get("sheet"))


# ── 5-3. 미달 사유 — 그 주 합계에 붙는다 ────────────────────────────
#
# 사유는 모델 한 줄씩이 아니라 주차 단위다. 화면의 '계획 미달 — 왜 못
# 채웠는지 적어 주세요' 와 같은 단위라야 올린 글이 거기 그대로 뜬다.
msr = mk(4, dev_type=True, part=False)
wbr = load_workbook(BytesIO(build(msr)))
wsr = wbr["2026-10"]
nfr = n_fixed(wsr)
n_rows_r = len(msr) + wt.SPARE_ROWS
r_sum = wt.FIRST_ROW + n_rows_r
r_note = r_sum + 1
ok(str(wsr.cell(r_sum, 1).value or "").strip() == "합계",
   "합계 줄이 %d행에 없다: %r" % (r_sum, wsr.cell(r_sum, 1).value))
ok(str(wsr.cell(r_note, 1).value or "").strip() == "미달 사유",
   "미달 사유 줄이 %d행에 없다: %r" % (r_note, wsr.cell(r_note, 1).value))
ok(str(wsr.cell(r_sum, nfr + 1).value or "").startswith("=IF(COUNT("),
   "합계 줄이 수식이 아니다: %r" % wsr.cell(r_sum, nfr + 1).value)

wsr.cell(wt.FIRST_ROW, nfr + 1, 20)
wsr.cell(wt.FIRST_ROW, nfr + 2, 12)
wsr.cell(r_note, nfr + 1, "자재 입고 지연 — 10/9 예정")
wsr.cell(r_note, nfr + 1 + wt.WEEK_N * 2, "고객 요청으로 출하 보류")
bufr = BytesIO()
wbr.save(bufr)
gr = pbx.parse(load_workbook(BytesIO(bufr.getvalue()), data_only=True))
ok(gr is not None, "사유를 적은 양식을 못 읽는다")
if gr:
    wk = gr["weeks"]
    ok(gr.get("week_notes") == {wk[0]: "자재 입고 지연 — 10/9 예정",
                                wk[2]: "고객 요청으로 출하 보류"},
       "주차 사유가 다르게 읽혔다: %r" % (gr.get("week_notes"),))
    # 사유 줄·합계 줄이 모델로 섞이면 안 된다
    labs = [r["label"] for r in gr["rows"]]
    ok("합계" not in labs and "미달 사유" not in labs,
       "합계·사유 줄을 모델로 읽었다: %s" % labs)
    ok(len(gr["rows"]) == 1, "숫자 적은 줄 1개만 와야 하는데 %d개" % len(gr["rows"]))


# ── 6. 라우트가 이 파서를 쓰는가 ────────────────────────────────────
MAIN = (BACK / "main.py").read_text(encoding="utf-8")
for frag, why in [
    ("def _pbx_pick_sheet(", "업로드가 쓰는 시트 고르기 함수가 없다"),
    ("/plan-file/preview", "미리보기 라우트가 없다"),
    ("/plan-file/apply", "저장 라우트가 없다"),
]:
    ok(frag in MAIN, why)

AV2 = (BACK / "admin_v2.html").read_text(encoding="utf-8")
ok("'/weekly-template'" in AV2, "양식 받기 버튼이 화면에 없다")
ok("plan-file/preview" in AV2, "올리기가 미리보기를 안 거친다")


if FAIL:
    print("실패 %d건" % len(FAIL))
    for f in FAIL:
        print("  -", f)
    raise SystemExit(1)
print("전부 통과 · 검사 8묶음 · 프로젝트 모양 %d가지" % len(SHAPES))
