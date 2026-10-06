"""블룸 일 보고 자료 — 빈 엑셀 양식.

기준은 '블룸_보고자료_Update_10_01_ver4_1.xlsx' 의 '10월 보고자료' 시트다.
그 모양을 그대로 만든다. 사람이 쓰던 파일이 기준이지 새로 짜낸 모양이
아니라서, 받는 분들이 지금 쓰던 대로 채우면 된다.

    A        B      C        D      E      F   G   │ H  I │ J  K │ ...
    품목     재고            공정    공정    10월 합계│ 1일   │ 2일   │
             출하   구매품    구분    재고    계획 실적│계획실적│계획실적│
             대기   대기

머리글이 세 줄인 게 핵심이다.
  1행  제목
  2행  품목 / 재고(병합) / 공정구분 / 공정재고 / N월 합계(병합) / 주차(병합)
  3행  출하대기 / 구매품대기 / 날짜
  4행  계획 / 실적

파서(bloom_daily_import)가 이 세 줄을 납작하게 펴서 열을 찾는다. 그래서
'공정⏎구분' 은 '공정구분' 으로 읽힌다 — 머리글 글자를 바꾸면 파서가 못
찾으니 양식과 파서를 같이 고쳐야 한다. 테스트가 둘을 묶어 둔다.

품목 칸은 세 줄(공정 NCT·조립·출하)을 세로 병합한다. 품목이 한 줄만
쓰는 경우(BOP Assy 는 NCT 가 없다)가 있어서 공정 수는 품목마다 다를 수
있다 — 양식은 세 줄로 깔고, 안 쓰는 줄은 비워 두면 된다.
"""

from __future__ import annotations

import calendar
import datetime as _dt
from io import BytesIO

from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

NAVY = "0F2C59"
HEAD = "1F3864"        # 머리글
SOFT = "F2F5F9"        # 품목 칸
PLAN = "ECF3FF"        # 계획
ACT = "FFF6ED"         # 실적
SUM_ = "EEF2F7"        # 월 합계
LINE = "BFC9D6"
KFONT = "맑은 고딕"

_thin = Side(style="thin", color=LINE)
BORDER = Border(left=_thin, right=_thin, top=_thin, bottom=_thin)

#: 왼쪽 고정 칸 — (머리글 2행, 머리글 3행, 너비)
FIXED = [
    ("품목", "", 15.8),
    ("재고", "출하\n대기", 10.8),
    ("재고", "구매품 \n대기", 10.8),
    ("공정\n구분", "", 14.0),
    ("공정\n재고", "", 10.8),
]
#: 한 품목이 쓰는 공정 줄
STEPS = ("NCT", "조립", "출하")
HDR_TITLE, HDR_TOP, HDR_MID, HDR_SUB = 1, 2, 3, 4
FIRST_ROW = 5


def _iso_week(d: _dt.date) -> int:
    return d.isocalendar()[1]


def month_days(month: str) -> list:
    y, m = int(month[:4]), int(month[5:7])
    last = calendar.monthrange(y, m)[1]
    return [_dt.date(y, m, d) for d in range(1, last + 1)]


def _h(ws, r, c, text, fill=HEAD, size=10):
    x = ws.cell(r, c, text)
    x.font = Font(name=KFONT, bold=True, size=size, color="FFFFFF")
    x.fill = PatternFill("solid", fgColor=fill)
    x.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
    x.border = BORDER
    return x


def build_bloom_template(month: str = "", items=None) -> bytes:
    """블룸 일 보고 자료 빈 양식.

    month  'YYYY-MM'. 없으면 이번 달.
    items  품목 이름 목록. 주면 왼쪽 칸을 채워 둔다 (숫자 칸은 비운다).
    """
    month = (month or _dt.date.today().strftime("%Y-%m")).strip()
    try:
        m = int(month[5:7])
        int(month[:4])
        if not (1 <= m <= 12):
            raise ValueError
    except Exception:
        raise ValueError("달을 YYYY-MM 으로 적어 주세요")

    days = month_days(month)
    items = [str(x).strip() for x in (items or []) if str(x).strip()]
    if not items:
        items = ["", "", "", "", "", "", ""]      # 빈 줄 일곱 품목

    wb = Workbook()
    ws = wb.active
    ws.title = "%d월 보고자료" % m

    nf = len(FIXED)
    sum_c = nf + 1                      # N월 합계 계획
    day_c0 = nf + 3                     # 첫 날짜 계획
    last_c = day_c0 + len(days) * 2 - 1
    note_c = last_c + 1

    # ── 1행 제목
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=7)
    t = ws.cell(1, 1, "블룸 계획 대비 실적 보고(%d/%02d)" % (m, 1))
    t.font = Font(name=KFONT, bold=True, size=16, color=NAVY)
    t.alignment = Alignment(horizontal="left", vertical="center")
    ws.row_dimensions[1].height = 42

    # ── 2~4행 왼쪽 고정 칸
    for i, (_t, _m2, w) in enumerate(FIXED, start=1):
        ws.column_dimensions[get_column_letter(i)].width = w
    # 품목 · 공정구분 · 공정재고 — 2~4행 세로 병합
    for i, label in ((1, "품목"), (4, "공정\n구분"), (5, "공정\n재고")):
        ws.merge_cells(start_row=HDR_TOP, start_column=i,
                       end_row=HDR_SUB, end_column=i)
        _h(ws, HDR_TOP, i, label)
    # 재고 — 2행에서 두 칸을 묶고, 그 아래 출하대기 / 구매품대기
    ws.merge_cells(start_row=HDR_TOP, start_column=2, end_row=HDR_TOP, end_column=3)
    _h(ws, HDR_TOP, 2, "재고")
    ws.cell(HDR_TOP, 3).border = BORDER
    for c, label in ((2, "출하\n대기"), (3, "구매품 \n대기")):
        ws.merge_cells(start_row=HDR_MID, start_column=c, end_row=HDR_SUB, end_column=c)
        _h(ws, HDR_MID, c, label)

    # ── N월 합계
    ws.merge_cells(start_row=HDR_TOP, start_column=sum_c,
                   end_row=HDR_MID, end_column=sum_c + 1)
    _h(ws, HDR_TOP, sum_c, "%d월 합계" % m)
    for j, lab in enumerate(("계획", "실적")):
        _h(ws, HDR_SUB, sum_c + j, lab)
        ws.column_dimensions[get_column_letter(sum_c + j)].width = 9.5

    # ── 날짜 — 주차로 묶고 그 아래 날짜, 그 아래 계획/실적
    c = day_c0
    wk_start, wk_no = c, _iso_week(days[0])
    for i, d in enumerate(days):
        ws.merge_cells(start_row=HDR_MID, start_column=c, end_row=HDR_MID, end_column=c + 1)
        dc = ws.cell(HDR_MID, c, _dt.datetime(d.year, d.month, d.day))
        dc.number_format = "yyyy-mm-dd"
        dc.font = Font(name=KFONT, bold=True, size=9, color="FFFFFF")
        dc.fill = PatternFill("solid", fgColor=HEAD)
        dc.alignment = Alignment(horizontal="center", vertical="center")
        dc.border = BORDER
        ws.cell(HDR_MID, c + 1).border = BORDER
        for j, lab in enumerate(("계획", "실적")):
            _h(ws, HDR_SUB, c + j, lab, size=9)
            ws.column_dimensions[get_column_letter(c + j)].width = 6.8
        nxt = _iso_week(days[i + 1]) if i + 1 < len(days) else None
        if nxt != wk_no:
            ws.merge_cells(start_row=HDR_TOP, start_column=wk_start,
                           end_row=HDR_TOP, end_column=c + 1)
            _h(ws, HDR_TOP, wk_start, "%d주차" % wk_no)
            wk_start, wk_no = c + 2, nxt
        c += 2

    ws.merge_cells(start_row=HDR_TOP, start_column=note_c,
                   end_row=HDR_SUB, end_column=note_c)
    _h(ws, HDR_TOP, note_c, "비고")
    ws.column_dimensions[get_column_letter(note_c)].width = 50.8

    for r in (HDR_TOP, HDR_MID, HDR_SUB):
        ws.row_dimensions[r].height = 29.25

    # ── 본문 — 품목 하나가 공정 세 줄
    body = Font(name=KFONT, size=10)
    f_soft = PatternFill("solid", fgColor=SOFT)
    f_plan = PatternFill("solid", fgColor=PLAN)
    f_act = PatternFill("solid", fgColor=ACT)
    f_sum = PatternFill("solid", fgColor=SUM_)
    r = FIRST_ROW
    for name in items:
        top = r
        for k, step in enumerate(STEPS):
            ws.row_dimensions[r].height = 24
            for ci in range(1, note_c + 1):
                cell = ws.cell(r, ci)
                cell.font = body
                cell.border = BORDER
                cell.alignment = Alignment(
                    horizontal="left" if ci in (1, 4, note_c) else "right",
                    vertical="center")
                if ci <= 3:
                    cell.fill = f_soft
                elif ci in (sum_c, sum_c + 1):
                    cell.fill = f_sum
                    cell.number_format = "#,##0"
                elif ci >= day_c0 and ci <= last_c:
                    cell.fill = f_plan if (ci - day_c0) % 2 == 0 else f_act
                    cell.number_format = "#,##0"
            ws.cell(r, 4, step)
            r += 1
        # 품목·재고 두 칸은 세 줄을 묶는다
        for ci in (1, 2, 3):
            ws.merge_cells(start_row=top, start_column=ci, end_row=r - 1, end_column=ci)
        a = ws.cell(top, 1, name or None)
        a.font = Font(name=KFONT, bold=True, size=10)
        a.alignment = Alignment(horizontal="left", vertical="center", wrap_text=True)

    ws.freeze_panes = ws.cell(FIRST_ROW, day_c0)
    ws.sheet_view.showGridLines = False
    ws.page_setup.orientation = "landscape"
    ws.page_setup.fitToWidth = 1
    ws.page_setup.fitToHeight = 0
    ws.sheet_properties.pageSetUpPr.fitToPage = True
    ws.print_title_rows = "%d:%d" % (HDR_TOP, HDR_SUB)

    _guide(wb, month, m)
    buf = BytesIO()
    wb.save(buf)
    return buf.getvalue()


def _guide(wb, month, m):
    g = wb.create_sheet("작성 안내")
    g.column_dimensions["A"].width = 18
    g.column_dimensions["B"].width = 92
    lines = [
        ("시트 이름", "'%d월 보고자료' 그대로 두세요. 한 파일에 여러 달을 둬도 되고, "
                      "그때는 가장 최근 달 시트를 읽습니다." % m),
        ("머리글 네 줄", "1행 제목 · 2행 품목/재고/공정구분/공정재고/%d월 합계/주차 · "
                        "3행 출하대기/구매품대기/날짜 · 4행 계획/실적. "
                        "이 글자들로 열을 찾으니 바꾸지 마세요." % m),
        ("품목", "세 줄(NCT·조립·출하)을 세로로 묶어 한 품목입니다. "
                 "공정이 두 줄뿐인 품목은 남는 줄을 비워 두면 됩니다."),
        ("공정 구분", "NCT · 조립 · 출하. 공장 이름을 괄호로 붙여도 됩니다 "
                      "(예: NCT(박닌)) — 괄호 앞까지만 보고 같은 공정으로 묶습니다."),
        ("계획 / 실적", "그 날 나갈 예정 수량과 실제로 나간 수량입니다. "
                        "파란 칸이 계획, 주황 칸이 실적입니다."),
        ("%s월 합계" % m, "그 달 전체 계획·실적입니다. 날짜 칸과 따로 적습니다."),
        ("비고", "맨 오른쪽 칸입니다. 그 공정 줄에 붙는 메모라서 "
                 "'부자재 10/5 입고' 처럼 그 줄에 관한 것만 적습니다."),
        ("확인이 필요한 것",
         "표 아래 빈 줄에 '◆ YFP 부자재 부족 ETA 10/5' 처럼 앞에 ◆ 를 붙여 "
         "적으면 화면의 '확인이 필요한 것' 에 그대로 올라갑니다. "
         "ETA 10/5 를 적으면 날짜도 같이 잡힙니다. "
         "◆ 대신 ■ ● - 도 됩니다."),
        ("", ""),
        ("같이 올라가는 것", "'현황 정리' 와 '금액 실적' 시트를 같은 파일에 두면 "
                             "한 번에 같이 읽습니다. 시트 이름을 그대로 쓰세요."),
        ("올리는 곳", "admin → 모델 관리 → 블룸 → 블룸 (전체) → 주차별 계획 → 엑셀 올리기. "
                      "품목별 화면에서는 올리지 않습니다."),
    ]
    r = 1
    for k, v in lines:
        a = g.cell(r, 1, k)
        a.font = Font(name=KFONT, bold=True, size=10, color=NAVY)
        a.alignment = Alignment(vertical="top")
        b = g.cell(r, 2, v)
        b.font = Font(name=KFONT, size=10)
        b.alignment = Alignment(vertical="top", wrap_text=True)
        g.row_dimensions[r].height = 34 if v else 10
        r += 1
    g.sheet_view.showGridLines = False
    # 안내는 A(제목) + B(설명) 두 칸이다. 그냥 두면 인쇄할 때 B 가 다음
    # 장으로 넘어가서, 제목만 있는 종이와 설명만 있는 종이가 따로 나온다.
    g.page_setup.orientation = "landscape"
    g.page_setup.fitToWidth = 1
    g.page_setup.fitToHeight = 0
    g.sheet_properties.pageSetUpPr.fitToPage = True
