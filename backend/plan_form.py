# -*- coding: utf-8 -*-
"""작성용 양식 — 한 해 한 장, 이번 달만 주차가 열린다.

### 왜 한 장인가

달마다 시트 한 장짜리 양식(weekly_template)은 이번 달만 보인다. 그런데
이번 주 계획을 적는 사람은 보통 "지난 달까지 얼마나 나갔더라" 를 보면서
적는다. 그걸 보려고 시트를 왔다 갔다 하거나 보드를 따로 띄워야 했다.

그래서 한 해를 한 장에 놓는다. 지난 달들은 **월 합계 두 칸**만 — 숫자를
보는 자리지 고치는 자리가 아니다. 이번 달만 주차 칸이 열려 있고, 거기
적어서 그대로 올리면 된다.

### 지난 달은 왜 주차 칸을 안 주나

올리는 쪽(pbx_plan_import)은 'W41' 처럼 **W 가 붙은 칸만** 읽고, 시트
이름으로 어느 달인지 정한다. 지난 달 주차 칸을 같이 두면 거기 적어도
조용히 안 읽힌다 — 적을 수 있게 생겼는데 안 먹는 칸이 제일 나쁘다.
그래서 아예 안 둔다. 지난 달을 고치려면 그 달로 받으면 된다.

### 보고용(plan_export)과 다르다

보고용은 진행현황 PPT 에 붙이는 것이라 유형별 묶음 합계가 있고 판가·
재료비가 없다. 이건 올리는 양식이라 반대다. 묶음 합계 줄도 없다 —
읽는 쪽이 '합계' 글자를 만나면 표가 끝난 줄 알아서, 중간에 두면 거기서
읽기가 끊긴다. 합계는 맨 아래 한 줄뿐이다.
"""

from __future__ import annotations

from io import BytesIO

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.datavalidation import DataValidation

import week_calendar as _wc
import weekly_template as _wt

NAVY = _wt.NAVY
HEAD2 = "1E3A5F"
BLUE = _wt.BLUE        # 이번 달 계획
WARM = _wt.WARM        # 이번 달 실적
GREY = _wt.GREY        # 수식
LOCK = _wt.LOCK        # 누구인지 — 건드리지 않는 칸
READ = "F1F5F9"        # 지난 달 월 합계 — 보기만
NOW = "B91C1C"         # 이번 달 머리글
NOTEBG = _wt.NOTEBG
SUMBG = _wt.SUMBG
KFONT = _wt.KFONT
BORDER = _wt.BORDER
DASH = "-"

ROW_TITLE = 1
HDR_TOP = 2            # 월 이름
HDR_WEEK = 3           # 주차 · 월 합계
HDR_SUB = 4            # 계획/실적
FIRST_ROW = 5
SPARE_ROWS = 8         # 새 모델 적을 빈 줄
SUB = ("계획", "실적")


def month_total(m: dict, ym: str) -> tuple:
    """그 달 주차를 더한 (계획, 실적). 적힌 게 하나도 없으면 (None, None).

    0 으로 적어 두면 '그 달에 하나도 안 나갔다' 로 읽힌다. 아직 아무것도
    안 적은 달과 구분되어야 한다.
    """
    bucket = (m.get("weekly_plan") or {}).get(str(ym))
    if not isinstance(bucket, dict):
        return (None, None)
    p = a = 0
    seen = False
    for cell in bucket.values():
        if not isinstance(cell, dict):
            continue
        for k, add in (("plan", "p"), ("actual", "a")):
            try:
                x = int(float(cell.get(k) or 0))
            except (TypeError, ValueError):
                x = 0
            if x:
                seen = True
                if add == "p":
                    p += x
                else:
                    a += x
    return (p, a) if seen else (None, None)


def layout(year: int, month: str) -> tuple:
    """달마다 자리 → (blocks, 앞쪽 칸 수는 호출하는 쪽이 준다)

    고른 달만 주차 칸을 갖는다. 나머지는 월 합계 두 칸.
    """
    out = []
    for i in range(1, 13):
        ym = "%04d-%02d" % (int(year), i)
        weeks = list(_wc.get_month_weeks(ym) or []) if ym == str(month) else []
        out.append({"month": ym, "weeks": weeks, "open": ym == str(month)})
    return out


def _head(ws, r, c, text, fill=NAVY, size=10):
    x = ws.cell(r, c, text)
    x.font = Font(name=KFONT, bold=True, size=size, color="FFFFFF")
    x.fill = PatternFill("solid", fgColor=fill)
    x.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
    x.border = BORDER
    return x


def build_year_form(project_label: str, year: int, month: str, models: list,
                    notes: dict = None) -> bytes:
    """작성용 한 해 양식 바이트.

    month  주차 칸을 열어 둘 달 ('2026-10'). 시트 이름도 이것이다 —
           올리는 쪽이 시트 이름으로 어느 달인지 정한다.
    """
    year = int(year)
    month = str(month).strip()
    if not _wc.get_month_weeks(month):
        raise ValueError("%s 는 주차가 없는 달입니다" % month)
    if not month.startswith("%04d-" % year):
        raise ValueError("%s 는 %d년이 아닙니다" % (month, year))

    models = _wt.order_models(models or [])
    cols = _wt.fixed_cols(models)
    nid = len(cols)
    n_val = len(_wt.VALUE)
    col_left = nid + n_val + 1              # 잔량
    nlead = col_left

    blocks = layout(year, month)
    c = nlead + 1
    for b in blocks:
        b["cols"] = [c + i * 2 for i in range(len(b["weeks"]))]
        b["total"] = c + len(b["weeks"]) * 2
        c = b["total"] + 2
    last = c - 1

    wb = Workbook()
    ws = wb.active
    ws.title = month

    body = Font(name=KFONT, size=10)
    lock_f = PatternFill("solid", fgColor=LOCK)
    read_f = PatternFill("solid", fgColor=READ)
    plan_f = PatternFill("solid", fgColor=BLUE)
    act_f = PatternFill("solid", fgColor=WARM)
    calc_f = PatternFill("solid", fgColor=GREY)

    # ── 제목 ─────────────────────────────────────────────────────────
    ws.merge_cells(start_row=ROW_TITLE, start_column=1,
                   end_row=ROW_TITLE, end_column=last)
    t = ws.cell(ROW_TITLE, 1,
                (("%s · " % project_label) if project_label else "")
                + "%d년 주차별 계획 · 실적    " % year
                + "[ %s 칸에만 적으시면 됩니다. 지난 달 '월 합계' 는 보기용이라 "
                  "고쳐도 안 올라갑니다 — 그 달을 고치려면 그 달로 받으세요 ]"
                % month)
    t.font = Font(name=KFONT, bold=True, size=11, color="FFFFFF")
    t.fill = PatternFill("solid", fgColor=NAVY)
    t.alignment = Alignment(horizontal="left", vertical="center", indent=1)
    ws.row_dimensions[ROW_TITLE].height = 26

    # ── 왼쪽 머리글 ──────────────────────────────────────────────────
    ci = 1
    for head, width, _key in cols:
        ws.merge_cells(start_row=HDR_TOP, start_column=ci,
                       end_row=HDR_SUB, end_column=ci)
        _head(ws, HDR_TOP, ci, head)
        ws.column_dimensions[get_column_letter(ci)].width = width
        ci += 1
    for head, width, _key, _fmt in _wt.VALUE:
        ws.merge_cells(start_row=HDR_TOP, start_column=ci,
                       end_row=HDR_SUB, end_column=ci)
        _head(ws, HDR_TOP, ci, head, fill=HEAD2)
        ws.column_dimensions[get_column_letter(ci)].width = width
        ci += 1
    ws.merge_cells(start_row=HDR_TOP, start_column=col_left,
                   end_row=HDR_SUB, end_column=col_left)
    _head(ws, HDR_TOP, col_left, "잔량", fill=HEAD2)
    ws.column_dimensions[get_column_letter(col_left)].width = 10

    # ── 달 머리글 ────────────────────────────────────────────────────
    for b in blocks:
        c0 = b["cols"][0] if b["cols"] else b["total"]
        ws.merge_cells(start_row=HDR_TOP, start_column=c0,
                       end_row=HDR_TOP, end_column=b["total"] + 1)
        _head(ws, HDR_TOP, c0,
              "%d월%s" % (int(b["month"][5:7]), "   ← 적는 달" if b["open"] else ""),
              fill=NOW if b["open"] else NAVY)
        for wk, wc in zip(b["weeks"], b["cols"]):
            ws.merge_cells(start_row=HDR_WEEK, start_column=wc,
                           end_row=HDR_WEEK, end_column=wc + 1)
            _head(ws, HDR_WEEK, wc, wk, fill=NOW)
            for j, s in enumerate(SUB):
                _head(ws, HDR_SUB, wc + j, s, fill=NOW)
                ws.column_dimensions[get_column_letter(wc + j)].width = 8
        ws.merge_cells(start_row=HDR_WEEK, start_column=b["total"],
                       end_row=HDR_WEEK, end_column=b["total"] + 1)
        _head(ws, HDR_WEEK, b["total"], "월 합계", fill=HEAD2)
        for j, s in enumerate(SUB):
            _head(ws, HDR_SUB, b["total"] + j, s, fill=HEAD2)
            ws.column_dimensions[get_column_letter(b["total"] + j)].width = 9

    ws.row_dimensions[HDR_TOP].height = 24
    ws.row_dimensions[HDR_WEEK].height = 18
    ws.row_dimensions[HDR_SUB].height = 18

    # ── 줄 ───────────────────────────────────────────────────────────
    L = get_column_letter
    r = FIRST_ROW
    for m in models:
        ci = 1
        for v in _wt._model_row(m, cols):
            x = ws.cell(r, ci, v)
            x.font = body
            x.fill = lock_f
            x.border = BORDER
            x.alignment = Alignment(horizontal="left", vertical="center")
            ci += 1
        for v, (_h, _w, _k, fmt) in zip(_wt._value_row(m), _wt.VALUE):
            x = ws.cell(r, ci, v)
            x.font = body
            x.border = BORDER
            x.number_format = fmt
            x.alignment = Alignment(horizontal="right", vertical="center")
            ci += 1

        # 잔량 — 한쪽이 비어 있어도 안 깨지게 SUM 으로 뺀다
        cpo = L(nid + 3)
        cshp = L(nid + 4)
        x = ws.cell(r, col_left,
                    '=IF(COUNT(%s%d:%s%d)=0,"",SUM(%s%d)-SUM(%s%d))'
                    % (cpo, r, cshp, r, cpo, r, cshp, r))
        x.font = Font(name=KFONT, size=10, bold=True, color=NAVY)
        x.fill = calc_f
        x.border = BORDER
        x.number_format = "#,##0"
        x.alignment = Alignment(horizontal="right", vertical="center")

        for b in blocks:
            if b["open"]:
                wk_vals = _wt.week_cells(m, b["month"])
                for wk, wc in zip(b["weeks"], b["cols"]):
                    got = wk_vals.get(wk) or {}
                    for j, key in enumerate(("plan", "actual")):
                        x = ws.cell(r, wc + j, got.get(key))
                        x.font = body
                        x.fill = plan_f if j == 0 else act_f
                        x.border = BORDER
                        x.number_format = "#,##0"
                        x.alignment = Alignment(horizontal="right",
                                                vertical="center")
                for j in range(2):
                    refs = ",".join("%s%d" % (L(wc + j), r) for wc in b["cols"])
                    x = ws.cell(r, b["total"] + j,
                                '=IF(COUNT(%s)=0,"",SUM(%s))' % (refs, refs))
                    x.font = Font(name=KFONT, size=10, bold=True, color=NAVY)
                    x.fill = calc_f
                    x.border = BORDER
                    x.number_format = "#,##0"
                    x.alignment = Alignment(horizontal="right", vertical="center")
            else:
                tot = month_total(m, b["month"])
                for j in range(2):
                    x = ws.cell(r, b["total"] + j,
                                tot[j] if tot[j] is not None else DASH)
                    x.font = body
                    x.fill = read_f
                    x.border = BORDER
                    x.number_format = "#,##0"
                    x.alignment = Alignment(horizontal="right", vertical="center")
        ws.row_dimensions[r].height = 17
        r += 1

    # 새 모델 적을 빈 줄 — 왼쪽 칸만 테두리를 둔다
    for _ in range(SPARE_ROWS):
        for ci2 in range(1, last + 1):
            x = ws.cell(r, ci2)
            x.font = body
            x.border = BORDER
            x.alignment = Alignment(horizontal="right", vertical="center")
            if ci2 <= nid:
                x.alignment = Alignment(horizontal="left", vertical="center")
        ws.row_dimensions[r].height = 17
        r += 1
    r_end = r - 1

    # ── 합계 · 미달 사유 ─────────────────────────────────────────────
    #
    # 묶음(유형별) 합계는 두지 않는다. 읽는 쪽이 '합계' 글자를 만나면 표가
    # 끝난 줄 알아서, 중간에 두면 그 아래 줄이 통째로 안 읽힌다.
    r_sum = r
    sum_f = PatternFill("solid", fgColor=SUMBG)
    sum_font = Font(name=KFONT, size=10, bold=True, color="FFFFFF")
    for ci2 in range(1, last + 1):
        x = ws.cell(r_sum, ci2)
        x.font = sum_font
        x.fill = sum_f
        x.border = BORDER
        x.number_format = "#,##0"
        x.alignment = Alignment(horizontal="right", vertical="center")
    lab = ws.cell(r_sum, 1, "합계")
    lab.alignment = Alignment(horizontal="left", vertical="center")
    for ci2 in range(nid + 3, last + 1):      # 판가·재료비는 더하지 않는다
        c2 = L(ci2)
        ws.cell(r_sum, ci2, '=IF(COUNT(%s%d:%s%d)=0,"",SUM(%s%d:%s%d))'
                % (c2, FIRST_ROW, c2, r_end, c2, FIRST_ROW, c2, r_end))
    ws.row_dimensions[r_sum].height = 20

    r_note = r_sum + 1
    note_f = PatternFill("solid", fgColor=NOTEBG)
    for ci2 in range(1, last + 1):
        x = ws.cell(r_note, ci2)
        x.font = body
        x.fill = note_f
        x.border = BORDER
        x.alignment = Alignment(horizontal="left", vertical="center",
                                wrap_text=True)
    nl = ws.cell(r_note, 1, "미달 사유")
    nl.font = Font(name=KFONT, size=10, bold=True, color=NAVY)
    if nlead >= 2:
        ws.merge_cells(start_row=r_note, start_column=1,
                       end_row=r_note, end_column=nlead)
    cur = next(b for b in blocks if b["open"])
    for wk, wc in zip(cur["weeks"], cur["cols"]):
        ws.merge_cells(start_row=r_note, start_column=wc,
                       end_row=r_note, end_column=wc + 1)
        txt = str((notes or {}).get(wk) or "").strip()
        if txt:
            ws.cell(r_note, wc, txt)
    ws.merge_cells(start_row=r_note, start_column=cur["total"],
                   end_row=r_note, end_column=cur["total"] + 1)
    x = ws.cell(r_note, cur["total"], "— 계획을 못 채운 주에만")
    x.font = Font(name=KFONT, size=9, color="94A3B8")
    ws.row_dimensions[r_note].height = 32

    # 구분은 새 줄을 적을 때 고르는 칸이다
    gi = next((i for i, c2 in enumerate(cols, start=1) if c2[2] == "group"), None)
    if gi:
        dv = DataValidation(type="list", formula1='"양산,개발"', allow_blank=True)
        ws.add_data_validation(dv)
        dv.add("%s%d:%s%d" % (L(gi), FIRST_ROW, L(gi), r_end))

    ws.freeze_panes = ws.cell(FIRST_ROW, nlead + 1)
    ws.sheet_view.showGridLines = False
    ws.page_setup.orientation = "landscape"
    ws.page_setup.fitToWidth = 1
    ws.page_setup.fitToHeight = 0
    ws.sheet_properties.pageSetUpPr.fitToPage = True
    ws.print_title_rows = "%d:%d" % (HDR_TOP, HDR_SUB)
    ws.print_area = "A1:%s%d" % (L(last), r_note)

    _guide(wb, project_label, year, month)

    buf = BytesIO()
    wb.save(buf)
    return buf.getvalue()


def _guide(wb, label, year, month):
    g = wb.create_sheet("작성 안내")
    g.column_dimensions["A"].width = 20
    g.column_dimensions["B"].width = 86
    g.merge_cells("A1:B1")
    t = g.cell(1, 1, "%s%d년 작성용 — 어디에 적나" % (("%s · " % label) if label else "", year))
    t.font = Font(name=KFONT, bold=True, size=12, color="FFFFFF")
    t.fill = PatternFill("solid", fgColor=NAVY)
    t.alignment = Alignment(horizontal="left", vertical="center", indent=1)
    g.row_dimensions[1].height = 26

    rows = [
        ("시트", "'%s' 한 장입니다. 한 해 열두 달이 가로로 늘어서 있습니다." % month),
        ("적는 칸", "%s 의 주차 칸(계획·실적)과 왼쪽의 판가·재료비·PO수량·"
                  "실적수량입니다." % month),
        ("지난 달", "월 합계 두 칸만 있고 보기용입니다. 고쳐도 올라가지 않습니다 — "
                  "그 달을 고치려면 달을 바꿔 다시 받으세요."),
        ("빈 칸", "한 줄에 숫자가 하나라도 있으면 그 줄의 %s 주차 칸은 **전부** "
                "파일대로 들어갑니다. 비운 칸은 0 이 됩니다. 한 줄을 통째로 "
                "비워 두면 그 줄은 손대지 않습니다." % month),
        ("판가·재료비·PO", "비어 있던 칸만 채웁니다. 이미 값이 있는 칸은 그대로 둡니다 — "
                       "덮어쓰려면 올릴 때 미리보기에서 고르세요."),
        ("새 모델", "맨 아래 빈 줄에 적으면 새로 만들어집니다. 모델명과 구분(양산/개발)은 "
                 "꼭 적어 주세요."),
        ("미달 사유", "맨 아래 줄입니다. 계획을 못 채운 주에만 그 주 칸에 적으시면 됩니다."),
        ("합계 줄", "자동 계산입니다. 건드리지 마세요."),
    ]
    r = 3
    for k, v in rows:
        a = g.cell(r, 1, k)
        a.font = Font(name=KFONT, bold=True, size=10, color=NAVY)
        a.alignment = Alignment(horizontal="left", vertical="top")
        b = g.cell(r, 2, v)
        b.font = Font(name=KFONT, size=10)
        b.alignment = Alignment(horizontal="left", vertical="top", wrap_text=True)
        g.row_dimensions[r].height = 30
        r += 1
    g.sheet_view.showGridLines = False
    return g
