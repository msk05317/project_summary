"""연간 내보내기 — 사람이 쓰던 '업데이트 N주차 계획' 모양 그대로.

주차별 계획 양식(weekly_template)은 **올리는** 양식이다. 한 달이 한 시트고
왼쪽에 판가·재료비가 있다. 이건 **보는** 양식이다 — 한 해가 한 시트고,
열두 달이 가로로 늘어서고, 돈 이야기가 없다.

    A  B      C        D    E     F     G   H   I   J   | 1월      | 2월 …
       묶음   파트넘버  PO   출하  잔여  9월 10월 11월 12월 | W02 W03 …
                                        └ 전년도 실적 ┘   | 계획 실적…

### 전년도 9~12월 (G~J)

표 안에 없는 넉 달이다. 올해 1월부터 그리니까 작년 말 넉 달은 칸이
없는데, 그 숫자를 보면서 올해를 읽던 자리라 따로 남긴다. OneView 에
작년 주차 자료가 있으면 더해서 채우고, 없으면 빈 칸으로 둔다 — 없는
숫자를 0 으로 적어 두면 '그 달에 하나도 안 나갔다' 로 읽힌다.

### 달력은 OneView 것을 쓴다

사람이 쓰던 파일은 1월을 W1~W5 로 적었는데 OneView 는 W02~W05 다
(W01 은 나흘이 12월이라 12월로 친다). 보드·주차 입력·엑셀 올리기가 전부
OneView 달력이라, 내보내기만 다르게 하면 받아서 다시 올렸을 때 첫 주가
안 붙는다.

### 빈 칸은 '-'

사람이 쓰던 파일이 그렇다. 0 과 '아직 없음' 이 눈으로 구분된다.
합계는 SUM 이라 '-' 를 건너뛴다 ('+' 로 더하면 #VALUE! 가 난다).
"""

from __future__ import annotations

from io import BytesIO

from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

import week_calendar as _wc

NAVY = "0F2C59"
HEAD2 = "1E3A5F"       # 머리글 아랫단
BLUE = "ECF3FF"        # 계획
WARM = "FFF6ED"        # 실적
GREY = "F1F5F9"        # 수식
LOCK = "F8FAFC"        # 건드리지 않는 칸
PREV = "FFF7ED"        # 전년도 실적
SUMBG = "0E2841"       # 묶음 합계
TOTBG = "334155"       # 총 합계
LINE = "D6DCE5"
KFONT = "맑은 고딕"

_thin = Side(style="thin", color=LINE)
BORDER = Border(left=_thin, right=_thin, top=_thin, bottom=_thin)

DASH = "-"             # 값이 없는 칸

# 왼쪽 고정 칸
COL_PAD = 1            # A — 비워 둔다 (사람이 쓰던 파일이 그렇다)
COL_GROUP = 2          # B — 묶음 라벨
COL_NAME = 3           # C — 파트넘버
COL_PO = 4             # D
COL_SHIP = 5           # E
COL_LEFT = 6           # F — 잔여수량 (= D - E)
COL_PREV0 = 7          # G~J — 전년도 9·10·11·12월 실적
PREV_MONTHS = (9, 10, 11, 12)
FIRST_MONTH_COL = COL_PREV0 + len(PREV_MONTHS)      # K
SUB = ("계획", "실적")

ROW_TOP = 2            # 월 이름
ROW_WEEK = 3           # 주차
ROW_SUB = 4            # 계획/실적
FIRST_ROW = 5


def months_of(year: int) -> list:
    """그 해 열두 달 → [('2026-01', ['W02', ...]), ...]"""
    out = []
    for m in range(1, 13):
        ym = "%04d-%02d" % (year, m)
        out.append((ym, list(_wc.get_month_weeks(ym) or [])))
    return out


def group_models(models: list) -> list:
    """유형으로 묶는다 → [(유형, [모델]), ...]

    순서는 등록된 순서 그대로다. 보기 좋으라고 이름순으로 다시 세우면,
    사람이 몇 달째 같은 자리에서 보던 줄이 매번 움직인다.
    """
    order, buckets = [], {}
    for m in models:
        if not isinstance(m, dict):
            continue
        dt = str(m.get("dev_type") or "").strip()
        if dt not in buckets:
            buckets[dt] = []
            order.append(dt)
        buckets[dt].append(m)
    # 유형이 없는 줄은 맨 아래로 — 거기 모여 있으면 '유형이 비었구나' 가 보인다
    order.sort(key=lambda d: (0 if d else 1,))
    return [(d, buckets[d]) for d in order]


def _n(v):
    try:
        x = float(v)
    except (TypeError, ValueError):
        return None
    return int(x) if x == int(x) else x


def week_cell(m: dict, ym: str, wk: str) -> tuple:
    """그 모델 · 그 달 · 그 주차 → (계획, 실적). 없으면 (None, None)."""
    got = ((m.get("weekly_plan") or {}).get(ym) or {}).get(wk)
    if not isinstance(got, dict):
        return (None, None)
    return (_n(got.get("plan")), _n(got.get("actual")))


def month_actual(m: dict, ym: str):
    """그 달 실적 합. 적힌 주차가 하나도 없으면 None (0 이 아니다)."""
    bucket = (m.get("weekly_plan") or {}).get(ym)
    if not isinstance(bucket, dict):
        return None
    tot, seen = 0, False
    for cell in bucket.values():
        if not isinstance(cell, dict):
            continue
        v = _n(cell.get("actual"))
        if v:
            tot += v
            seen = True
    return tot if seen else None


def _head(ws, r, c, text, fill=NAVY, size=10):
    x = ws.cell(r, c, text)
    x.font = Font(name=KFONT, bold=True, size=size, color="FFFFFF")
    x.fill = PatternFill("solid", fgColor=fill)
    x.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
    x.border = BORDER
    return x


def _layout(mons: list) -> tuple:
    """달마다 (시작열, 주차열들, 월합계열) · 마지막 열"""
    plan, c = [], FIRST_MONTH_COL
    for ym, wks in mons:
        wcols = [c + i * 2 for i in range(len(wks))]
        tot = c + len(wks) * 2
        plan.append({"month": ym, "weeks": wks, "cols": wcols, "total": tot})
        c = tot + 2
    return plan, c - 1


def months_with_weeks(models: list, year: int) -> list:
    """그 해에 주차 숫자가 하나라도 적힌 달."""
    out = set()
    for m in models or []:
        if not isinstance(m, dict):
            continue
        for ym, bucket in (m.get("weekly_plan") or {}).items():
            if not str(ym).startswith("%04d-" % int(year)):
                continue
            if not isinstance(bucket, dict):
                continue
            for cell in bucket.values():
                if isinstance(cell, dict) and (cell.get("plan") or cell.get("actual")):
                    out.add(str(ym))
                    break
    return sorted(out)


def build_year_export(project_label: str, year: int, models: list,
                      sheet_name: str = "", expand=None) -> bytes:
    """한 해치 주차별 계획·실적 엑셀 바이트.

    expand  주차를 펼쳐 둘 달 ['2026-09', ...]. 안 주면 주차 숫자가 적힌
            달만 펼친다. 나머지 달은 주차 칸을 접어서 **월 합계 두 칸만**
            보인다 — 쉰두 주를 다 늘어놓으면 눈이 어디를 봐야 할지 모른다.

            접은 것뿐이라 지워지지 않는다. 엑셀에서 머리 위 [+] 를 누르면
            그 자리에서 펼쳐진다 — 달을 바꿔 보려고 다시 뽑을 일이 없다.
    """
    year = int(year)
    mons = months_of(year)
    if expand is None:
        expand = months_with_weeks(models, year)
    open_set = {str(x).strip() for x in (expand or []) if str(x).strip()}
    blocks, last = _layout(mons)
    groups = group_models([m for m in (models or []) if isinstance(m, dict)])
    prev_y = year - 1

    wb = Workbook()
    ws = wb.active
    ws.title = (sheet_name or project_label or "PLAN").strip()[:31]

    body = Font(name=KFONT, size=10)
    lock_f = PatternFill("solid", fgColor=LOCK)
    plan_f = PatternFill("solid", fgColor=BLUE)
    act_f = PatternFill("solid", fgColor=WARM)
    calc_f = PatternFill("solid", fgColor=GREY)
    prev_f = PatternFill("solid", fgColor=PREV)

    # ── 머리글 ───────────────────────────────────────────────────────
    ws.column_dimensions["A"].width = 3
    ws.merge_cells(start_row=ROW_TOP, start_column=COL_GROUP,
                   end_row=ROW_SUB, end_column=COL_GROUP)
    _head(ws, ROW_TOP, COL_GROUP, "")
    ws.column_dimensions[get_column_letter(COL_GROUP)].width = 11

    ws.merge_cells(start_row=ROW_TOP, start_column=COL_NAME,
                   end_row=ROW_SUB, end_column=COL_NAME)
    _head(ws, ROW_TOP, COL_NAME, "파트넘버")
    ws.column_dimensions[get_column_letter(COL_NAME)].width = 20

    ws.merge_cells(start_row=ROW_TOP, start_column=COL_PO,
                   end_row=ROW_WEEK, end_column=COL_LEFT)
    _head(ws, ROW_TOP, COL_PO, "Total")
    for c, name in ((COL_PO, "PO수량"), (COL_SHIP, "출하실적"), (COL_LEFT, "잔여수량")):
        _head(ws, ROW_SUB, c, name, fill=HEAD2)
        ws.column_dimensions[get_column_letter(c)].width = 11

    for i, m in enumerate(PREV_MONTHS):
        c = COL_PREV0 + i
        ws.merge_cells(start_row=ROW_TOP, start_column=c, end_row=ROW_SUB, end_column=c)
        _head(ws, ROW_TOP, c, "%d년\n%d월 실적" % (prev_y, m), size=9)
        ws.column_dimensions[get_column_letter(c)].width = 10

    for b in blocks:
        c0, n = b["cols"][0] if b["cols"] else b["total"], len(b["weeks"])
        ws.merge_cells(start_row=ROW_TOP, start_column=c0,
                       end_row=ROW_TOP, end_column=b["total"] + 1)
        _head(ws, ROW_TOP, c0, "%d월" % int(b["month"][5:7]))
        for wk, wc in zip(b["weeks"], b["cols"]):
            ws.merge_cells(start_row=ROW_WEEK, start_column=wc,
                           end_row=ROW_WEEK, end_column=wc + 1)
            _head(ws, ROW_WEEK, wc, wk, fill=HEAD2)
            for j, s in enumerate(SUB):
                _head(ws, ROW_SUB, wc + j, s, fill=HEAD2)
                ws.column_dimensions[get_column_letter(wc + j)].width = 8
        ws.merge_cells(start_row=ROW_WEEK, start_column=b["total"],
                       end_row=ROW_WEEK, end_column=b["total"] + 1)
        _head(ws, ROW_WEEK, b["total"], "월 합계", fill=HEAD2)
        for j, s in enumerate(SUB):
            _head(ws, ROW_SUB, b["total"] + j, s, fill=HEAD2)
            ws.column_dimensions[get_column_letter(b["total"] + j)].width = 9
        _ = n

    ws.row_dimensions[ROW_TOP].height = 30
    ws.row_dimensions[ROW_WEEK].height = 18
    ws.row_dimensions[ROW_SUB].height = 18

    # ── 줄 ───────────────────────────────────────────────────────────
    r = FIRST_ROW
    sum_rows = []
    for dev_type, ms in groups:
        start = r
        for i, m in enumerate(ms):
            # 묶음 라벨 — 첫 줄에 유형, 둘째 줄에 '베이스'
            if i == 0:
                lab = ("-%s" % dev_type) if dev_type else "(유형 없음)"
                g = ws.cell(r, COL_GROUP, lab)
                g.font = Font(name=KFONT, bold=True, size=10, color=NAVY)
            elif i == 1:
                g = ws.cell(r, COL_GROUP, "베이스")
                g.font = Font(name=KFONT, bold=True, size=10, color=NAVY)
            else:
                g = ws.cell(r, COL_GROUP)
                g.font = body
            g.fill = lock_f
            g.border = BORDER
            g.alignment = Alignment(horizontal="left", vertical="center")

            c = ws.cell(r, COL_NAME, str(m.get("name") or m.get("id") or ""))
            c.font = body
            c.fill = lock_f
            c.border = BORDER
            c.alignment = Alignment(horizontal="left", vertical="center")

            for col, key in ((COL_PO, "po_qty"), (COL_SHIP, "shipped_qty")):
                v = _n(m.get(key))
                x = ws.cell(r, col, v if v is not None else DASH)
                x.font = body
                x.border = BORDER
                x.number_format = "#,##0"
                x.alignment = Alignment(horizontal="right", vertical="center")

            L = get_column_letter
            # 둘 중 하나가 '-' 여도 빼진다. 그냥 D-E 로 쓰면 PO 만 있고 출하가
            # 아직 '-' 인 줄(301 이 그렇다)에서 #VALUE! 가 난다 — SUM 은 글자를
            # 건너뛰어 0 으로 본다.
            x = ws.cell(r, COL_LEFT,
                        '=IF(COUNT(%s%d:%s%d)=0,"-",SUM(%s%d)-SUM(%s%d))'
                        % (L(COL_PO), r, L(COL_SHIP), r,
                           L(COL_PO), r, L(COL_SHIP), r))
            x.font = Font(name=KFONT, size=10, bold=True, color=NAVY)
            x.fill = calc_f
            x.border = BORDER
            x.number_format = "#,##0"
            x.alignment = Alignment(horizontal="right", vertical="center")

            # 전년도 9~12월 실적 — 있으면 쓰고 없으면 빈 칸
            for i2, mm in enumerate(PREV_MONTHS):
                v = month_actual(m, "%04d-%02d" % (prev_y, mm))
                x = ws.cell(r, COL_PREV0 + i2, v if v is not None else DASH)
                x.font = body
                x.fill = prev_f
                x.border = BORDER
                x.number_format = "#,##0"
                x.alignment = Alignment(horizontal="right", vertical="center")

            for b in blocks:
                for wk, wc in zip(b["weeks"], b["cols"]):
                    vals = week_cell(m, b["month"], wk)
                    for j in range(2):
                        x = ws.cell(r, wc + j,
                                    vals[j] if vals[j] is not None else DASH)
                        x.font = body
                        x.fill = plan_f if j == 0 else act_f
                        x.border = BORDER
                        x.number_format = "#,##0"
                        x.alignment = Alignment(horizontal="right", vertical="center")
                for j in range(2):
                    cells = ",".join("%s%d" % (L(wc + j), r) for wc in b["cols"])
                    x = ws.cell(r, b["total"] + j,
                                '=IF(COUNT(%s)=0,"-",SUM(%s))' % (cells, cells)
                                if cells else DASH)
                    x.font = Font(name=KFONT, size=10, bold=True, color=NAVY)
                    x.fill = calc_f
                    x.border = BORDER
                    x.number_format = "#,##0"
                    x.alignment = Alignment(horizontal="right", vertical="center")
            ws.row_dimensions[r].height = 17
            r += 1

        # 묶음 합계
        _sum_row(ws, r, start, r - 1, last, "합계", SUMBG)
        sum_rows.append(r)
        r += 1

    # 총 합계 — 묶음 합계끼리 더한다 (모델 줄을 다시 더하면 두 번 세어진다)
    if sum_rows:
        _total_row(ws, r, sum_rows, last)

    # 주차 칸 접기 — 월 합계 두 칸은 남긴다.
    #
    # 접힌 달도 '그 달 계획·실적' 은 보인다. 주차만 안 보일 뿐이라
    # 한 해를 훑다가 궁금한 달만 [+] 로 펼치면 된다.
    for b in blocks:
        if not b["cols"] or b["month"] in open_set:
            continue
        ws.column_dimensions.group(
            get_column_letter(b["cols"][0]),
            get_column_letter(b["cols"][-1] + 1),
            hidden=True, outline_level=1)

    ws.freeze_panes = ws.cell(FIRST_ROW, FIRST_MONTH_COL)
    ws.sheet_view.showGridLines = False
    # 인쇄 — 세로로는 한 장(줄이 스무 개뿐), 가로로는 필요한 만큼 이어서.
    # 가로까지 한 장에 맞추면 열두 달 백서른 칸이 한 장에 뭉개져 아무것도 안 보인다.
    ws.page_setup.orientation = "landscape"
    ws.page_setup.fitToHeight = 1
    ws.page_setup.fitToWidth = 0
    ws.sheet_properties.pageSetUpPr.fitToPage = True
    ws.print_title_cols = "%s:%s" % (get_column_letter(COL_GROUP),
                                     get_column_letter(COL_NAME))
    ws.print_title_rows = "%d:%d" % (ROW_TOP, ROW_SUB)

    buf = BytesIO()
    wb.save(buf)
    return buf.getvalue()


def _sum_row(ws, r, r0, r1, last, label, bg):
    f = PatternFill("solid", fgColor=bg)
    font = Font(name=KFONT, size=10, bold=True, color="FFFFFF")
    L = get_column_letter
    for c in range(COL_GROUP, last + 1):
        x = ws.cell(r, c)
        x.font = font
        x.fill = f
        x.border = BORDER
        x.number_format = "#,##0"
        x.alignment = Alignment(horizontal="right", vertical="center")
    lab = ws.cell(r, COL_NAME, label)
    lab.alignment = Alignment(horizontal="left", vertical="center")
    if r1 >= r0:
        for c in range(COL_PO, last + 1):
            ws.cell(r, c, '=IF(COUNT(%s%d:%s%d)=0,"-",SUM(%s%d:%s%d))'
                    % (L(c), r0, L(c), r1, L(c), r0, L(c), r1))
    ws.row_dimensions[r].height = 19


def _total_row(ws, r, sum_rows, last):
    f = PatternFill("solid", fgColor=TOTBG)
    font = Font(name=KFONT, size=10, bold=True, color="FFFFFF")
    L = get_column_letter
    for c in range(COL_GROUP, last + 1):
        x = ws.cell(r, c)
        x.font = font
        x.fill = f
        x.border = BORDER
        x.number_format = "#,##0"
        x.alignment = Alignment(horizontal="right", vertical="center")
    ws.merge_cells(start_row=r, start_column=COL_GROUP,
                   end_row=r, end_column=COL_NAME)
    lab = ws.cell(r, COL_GROUP, "총 합계")
    lab.alignment = Alignment(horizontal="left", vertical="center")
    for c in range(COL_PO, last + 1):
        refs = ",".join("%s%d" % (L(c), x) for x in sum_rows)
        ws.cell(r, c, '=IF(COUNT(%s)=0,"-",SUM(%s))' % (refs, refs))
    ws.row_dimensions[r].height = 20
