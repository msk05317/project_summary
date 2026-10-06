"""주차별 계획·실적 엑셀 양식.

시트 한 장이 한 달이다. 시트 이름이 곧 그 달(2026-09)이라 파서가 달을
추측하지 않아도 된다. 여러 달을 한 파일에 넣어도 된다.

    A        B        C     D     │  W36   │  W37   │ ...  │  월 합계
    파트넘버  모델명    유형   구분  │ 계획 실적│ 계획 실적│      │ 계획 실적

머리글이 두 줄인 이유가 있다. 한 줄로 'W36계획 W36실적' 처럼 쓰면 열
이름이 길어져 사람이 못 읽고, 달이 바뀔 때마다 열 이름을 통째로 다시
쓰게 된다. 위에 주차를 병합해 두면 눈으로도 묶여 보이고 파서도 '어느
열이 몇 주차인지' 를 한 번만 찾으면 된다. 잔·특근 엑셀이 이미 이 모양이다.

### 모델 칸은 미리 채운다

매주 품번 열다섯 개를 손으로 적게 하면 언젠가 하나를 다르게 적는다.
다르게 적힌 줄은 어느 모델에도 안 붙어서 조용히 사라진다 — 엔클로저의
615·612·301 이 주차 데이터 없이 비어 있던 게 그 모양이다. 그래서 모델
목록이 있으면 왼쪽 네 칸을 채워서 내보낸다. 사람은 숫자만 적는다.

### 빈 칸은 '그대로 둬라'

매주 같은 파일을 열어 그 주 실적만 채워 다시 올린다. 안 적은 칸이 0 으로
들어가면 지난 주차 실적이 매번 날아간다. 0 으로 만들고 싶으면 0 을 적는다.
"""

from __future__ import annotations

from io import BytesIO

from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.datavalidation import DataValidation

NAVY = "0F2C59"
BLUE = "ECF3FF"        # 계획 칸
WARM = "FFF6ED"        # 실적 칸
GREY = "F1F5F9"        # 수식
LOCK = "F8FAFC"        # 건드리지 말아야 할 칸 (모델 정보)
LINE = "D6DCE5"
KFONT = "맑은 고딕"

_thin = Side(style="thin", color=LINE)
BORDER = Border(left=_thin, right=_thin, top=_thin, bottom=_thin)

# 왼쪽 고정 칸 — (머리글, 너비, 모델에서 꺼낼 키)
#
# 앞쪽 네 칸은 '이 줄이 누구인가' 다. 뒤쪽 네 칸은 '그 모델에 대한 값' 이고
# 적어 넣을 수 있다. 예전에는 뒤쪽이 '모델 등록 양식' 이라는 다른 파일에
# 있었는데, 새 모델이 하나 생길 때마다 두 파일을 만져야 했다.
FIXED = [
    ("파트넘버", 18, "part_number"),
    ("모델명", 24, "name"),
    ("유형", 10, "dev_type"),
    ("구분", 9, "group"),
]
#: 적어 넣는 칸 — (머리글, 너비, 키, 숫자서식)
VALUE = [
    ("판가($)", 12, "price", '#,##0.00'),
    ("재료비($)", 12, "material_cost", '#,##0.00'),
    ("PO수량", 10, "po_qty", '#,##0'),
    ("실적수량", 10, "shipped_qty", '#,##0'),
]
WEEK_SUB = ("계획", "실적")
WEEK_W = 9
WEEK_N = len(WEEK_SUB)
# 미달 사유는 주차마다가 아니라 맨 오른쪽 한 칸이다. 주차마다 두면 표가
# 세 배로 넓어지는데, 정작 적는 일은 한 달에 한두 줄뿐이다.
NOTEBG = "FFFDF5"      # 미달 사유 줄
SUMBG = "0E2841"       # 합계 줄
SPARE_ROWS = 12        # 목록 아래 여분 (새 모델 적을 자리)
BLANK_ROWS = 40        # 모델 목록이 없을 때 빈 줄
HDR_TOP = 2            # 주차가 들어가는 줄
HDR_SUB = 3            # 계획/실적 줄
FIRST_ROW = 4


#: 늘 두는 칸 — 줄을 알아보는 칸(모델명)과 새 모델을 적을 때 고르는 칸(구분)
ALWAYS = ("name", "group")


def fixed_cols(models: list) -> list:
    """그 프로젝트가 실제로 쓰는 왼쪽 칸만.

    파트넘버가 하나도 없는 프로젝트에 파트넘버 칸을 두면, 사람들이 거기
    뭔가 적는다. 적힌 건 어느 모델에도 안 붙어 조용히 사라진다. 모델
    목록이 아예 없는 빈 양식은 네 칸을 다 둔다 — 무엇을 쓸지 모르니까.
    """
    ms = [m for m in (models or []) if isinstance(m, dict)]
    if not ms:
        return list(FIXED)
    out = []
    for col in FIXED:
        key = col[2]
        if key in ALWAYS or any(str(m.get(key) or "").strip() for m in ms):
            out.append(col)
    return out


def _model_row(m: dict, cols=None) -> list:
    out = []
    for _h, _w, key in (cols or FIXED):
        v = m.get(key)
        s = "" if v is None else str(v).strip()
        if key == "group":
            s = "개발" if s == "개발" else "양산"
        if key == "name" and not s:
            s = str(m.get("id") or "").strip()
        out.append(s)
    return out


def _value_row(m: dict) -> list:
    """적어 넣는 칸의 지금 값. 0 은 빈 칸으로 둔다.

    0 을 찍어 두면 '아직 안 정한 것' 과 '정말 0' 이 구분되지 않는다.
    빈 칸으로 두면 임포터가 '그대로 둬라' 로 읽으니 손해도 없다.
    """
    out = []
    for _h, _w, key, _f in VALUE:
        v = m.get(key)
        try:
            x = float(v)
        except (TypeError, ValueError):
            x = 0.0
        out.append(x if x else None)
    return out


def week_cells(m: dict, month: str) -> dict:
    """그 모델의 그 달 주차 숫자 → {'W41': {'plan': 20, 'actual': 12}}.

    0 과 빈 칸을 구분하지 않고 둘 다 빈 칸으로 낸다. 양식의 빈 칸은
    '그대로 둬라' 라서, 0 을 빈 칸으로 보내도 다시 올릴 때 0 이 0 으로
    남는다 — 손해가 없고, 0 이 깔린 표보다 읽기 쉽다.
    """
    wp = m.get("weekly_plan")
    if not isinstance(wp, dict):
        return {}
    got = wp.get(str(month))
    if not isinstance(got, dict):
        return {}
    out = {}
    for w, v in got.items():
        if not isinstance(v, dict):
            continue
        cell = {}
        for k in ("plan", "actual"):
            try:
                x = int(float(v.get(k) or 0))
            except (TypeError, ValueError):
                x = 0
            if x:
                cell[k] = x
        if cell:
            out[str(w).strip().upper()] = cell
    return out


def order_models(models: list) -> list:
    """양식에 놓을 순서 — 유형끼리 모으고, 그 안에서 이름순.

    주차 보드가 유형으로 줄을 묶으니 양식도 같은 순서여야 한다. 보드에서
    '413 직납' 을 보다가 양식을 열면 413 이 붙어 있어야 눈이 안 흩어진다.
    유형이 없는 모델은 맨 아래로 내린다 — 거기 모여 있으면 '이것들 유형이
    비었구나' 가 바로 보인다.
    """
    def key(m):
        dt = str(m.get("dev_type") or "").strip()
        nm = str(m.get("name") or m.get("id") or "").strip()
        pn = str(m.get("part_number") or "").strip()
        return (1 if not dt else 0, dt, nm, pn)
    return sorted([m for m in models if isinstance(m, dict)], key=key)


def duplicate_rows(models: list) -> list:
    """양식에서 서로 구분이 안 되는 줄.

    파서는 파트넘버로 찾고, 없으면 모델명으로 찾는다. 둘 다 같은 줄이
    여럿이면 어느 줄의 숫자인지 알 수 없다 — 큐리의 '버스바' 다섯 줄이
    파트넘버 없이 들어오면 그렇게 된다. 양식을 내보내기 전에 알려 준다.
    """
    seen, dup = {}, []
    for m in models:
        if not isinstance(m, dict):
            continue
        pn = str(m.get("part_number") or "").strip().lower()
        nm = str(m.get("name") or m.get("id") or "").strip().lower()
        k = ("pn", pn) if pn else ("nm", nm)
        if not k[1]:
            continue
        if k in seen:
            dup.append({"name": m.get("name") or m.get("id"),
                        "part_number": m.get("part_number") or "",
                        "same_as": seen[k]})
        else:
            seen[k] = m.get("name") or m.get("id")
    return dup


def _title(ws, last_col, text):
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=last_col)
    c = ws.cell(1, 1, text)
    c.font = Font(name=KFONT, bold=True, size=11, color="FFFFFF")
    c.fill = PatternFill("solid", fgColor=NAVY)
    c.alignment = Alignment(horizontal="left", vertical="center", indent=1)
    ws.row_dimensions[1].height = 26


def _head_cell(ws, r, c, text, fill=NAVY):
    x = ws.cell(r, c, text)
    x.font = Font(name=KFONT, bold=True, size=10, color="FFFFFF")
    x.fill = PatternFill("solid", fgColor=fill)
    x.alignment = Alignment(horizontal="center", vertical="center")
    x.border = BORDER
    return x


def _sheet(wb, month: str, weeks: list, models: list, label: str, first: bool,
           filled: bool = False, notes: dict = None):
    ws = wb.create_sheet(month) if not first else wb.active
    if first:
        ws.title = month

    cols = fixed_cols(models)
    nf = len(cols) + len(VALUE)             # 왼쪽 = 누구인가 + 그 모델 값
    nid = len(cols)                         # 그중 '누구인가' 칸 수
    last = nf + len(weeks) * WEEK_N + 2    # + 월 합계 2칸

    _title(ws, last, (f"{label} · " if label else "")
           + f"{month} 주차별 계획 · 실적    "
           + "[ 회색 %d칸(누구인지)과 월 합계는 건드리지 마세요. "
             "판가·재료비·PO·실적과 주차 칸은 적으시면 됩니다 ]    " % nid
           + ("지금 숫자가 채워져 있습니다 — 이번 주 칸만 더 적어 그대로 올리세요."
              if filled else
              "한 줄을 통째로 비워 두면 그 줄은 건드리지 않습니다."))

    # ── 머리글 두 줄
    for i, (name, width, _k) in enumerate(cols, start=1):
        ws.merge_cells(start_row=HDR_TOP, start_column=i, end_row=HDR_SUB, end_column=i)
        _head_cell(ws, HDR_TOP, i, name)
        ws.column_dimensions[get_column_letter(i)].width = width
    for j, (name, width, _k, _f) in enumerate(VALUE):
        i = nid + 1 + j
        ws.merge_cells(start_row=HDR_TOP, start_column=i, end_row=HDR_SUB, end_column=i)
        _head_cell(ws, HDR_TOP, i, name)
        ws.column_dimensions[get_column_letter(i)].width = width

    for wi, wk in enumerate(weeks):
        c0 = nf + wi * WEEK_N + 1
        ws.merge_cells(start_row=HDR_TOP, start_column=c0,
                       end_row=HDR_TOP, end_column=c0 + WEEK_N - 1)
        _head_cell(ws, HDR_TOP, c0, wk)
        for j, sub in enumerate(WEEK_SUB):
            _head_cell(ws, HDR_SUB, c0 + j, sub)
            ws.column_dimensions[get_column_letter(c0 + j)].width = WEEK_W

    c0 = nf + len(weeks) * WEEK_N + 1
    ws.merge_cells(start_row=HDR_TOP, start_column=c0, end_row=HDR_TOP, end_column=c0 + 1)
    _head_cell(ws, HDR_TOP, c0, "월 합계")
    for j, sub in enumerate(WEEK_SUB):
        _head_cell(ws, HDR_SUB, c0 + j, sub)
        ws.column_dimensions[get_column_letter(c0 + j)].width = 10
    ws.row_dimensions[HDR_TOP].height = 20
    ws.row_dimensions[HDR_SUB].height = 18

    # ── 줄
    body = Font(name=KFONT, size=10)
    lock_f = PatternFill("solid", fgColor=LOCK)
    plan_f = PatternFill("solid", fgColor=BLUE)
    act_f = PatternFill("solid", fgColor=WARM)
    note_f = PatternFill("solid", fgColor=NOTEBG)
    calc_f = PatternFill("solid", fgColor=GREY)
    n_rows = (len(models) + SPARE_ROWS) if models else BLANK_ROWS

    for i in range(n_rows):
        r = FIRST_ROW + i
        has = bool(models and i < len(models))
        vals = _model_row(models[i], cols) if has else None
        vvals = _value_row(models[i]) if has else None
        # 누구인지 칸 — 회색. 고치면 다른 모델이 되거나 못 찾는다.
        for ci in range(1, nid + 1):
            c = ws.cell(r, ci)
            c.font = body
            c.border = BORDER
            c.fill = lock_f
            c.alignment = Alignment(horizontal="left", vertical="center")
            if vals and vals[ci - 1]:
                c.value = vals[ci - 1]
        # 적어 넣는 칸 — 흰색. 비워 두면 지금 값이 그대로 남는다.
        for j, (_h, _w, _k, fmt) in enumerate(VALUE):
            c = ws.cell(r, nid + 1 + j)
            c.font = body
            c.border = BORDER
            c.number_format = fmt
            c.alignment = Alignment(horizontal="right", vertical="center")
            if vvals and vvals[j] is not None:
                c.value = vvals[j]
        # 지금 올라가 있는 주차 숫자 (내보내기)
        wkv = week_cells(models[i], month) if (has and filled) else {}
        for wi, wname in enumerate(weeks):
            cell = wkv.get(wname) or {}
            for j in range(WEEK_N):
                c = ws.cell(r, nf + wi * WEEK_N + 1 + j)
                c.font = body
                c.border = BORDER
                c.fill = plan_f if j == 0 else act_f
                c.number_format = "#,##0"
                c.alignment = Alignment(horizontal="right", vertical="center")
                v = cell.get("plan" if j == 0 else "actual")
                if v:
                    c.value = v
        # 월 합계 = 수식
        for j in range(2):
            c = ws.cell(r, c0 + j)
            c.font = Font(name=KFONT, size=10, bold=True, color=NAVY)
            c.border = BORDER
            c.fill = calc_f
            c.number_format = "#,##0"
            c.alignment = Alignment(horizontal="right", vertical="center")
            cells = ",".join(
                "%s%d" % (get_column_letter(nf + wi * WEEK_N + 1 + j), r)
                for wi in range(len(weeks)))
            # 빈 줄까지 0 이 깔리면 눈이 거기로 끌린다. 아무것도 없으면 빈 칸.
            c.value = '=IF(COUNT(%s)=0,"",SUM(%s))' % (cells, cells)
        ws.row_dimensions[r].height = 18

    # ── 합계 줄 + 미달 사유 줄
    #
    # 미달 사유는 모델 한 줄씩이 아니라 **그 주 합계**에 붙는다. 화면의
    # '계획 미달 — 왜 못 채웠는지 적어 주세요' 와 같은 단위다. 품목별로
    # 따지지 않는 이유도 같다 — 한 주에 왜 못 채웠는지는 보통 한 가지다.
    r_end = FIRST_ROW + n_rows - 1
    r_sum = r_end + 1
    r_note = r_sum + 1

    sum_f = PatternFill("solid", fgColor=SUMBG)
    sum_font = Font(name=KFONT, size=10, bold=True, color="FFFFFF")
    for ci in range(1, last + 1):
        c = ws.cell(r_sum, ci)
        c.font = sum_font
        c.fill = sum_f
        c.border = BORDER
        c.alignment = Alignment(horizontal="right", vertical="center")
        c.number_format = "#,##0"
    lab = ws.cell(r_sum, 1, "합계")
    lab.alignment = Alignment(horizontal="left", vertical="center")
    for ci in range(nf + 1, last + 1):
        L = get_column_letter(ci)
        ws.cell(r_sum, ci,
                '=IF(COUNT(%s%d:%s%d)=0,"",SUM(%s%d:%s%d))'
                % (L, FIRST_ROW, L, r_end, L, FIRST_ROW, L, r_end))
    ws.row_dimensions[r_sum].height = 20

    # 미달 사유 — 주차마다 한 칸 (계획·실적 두 칸을 묶는다)
    for ci in range(1, last + 1):
        c = ws.cell(r_note, ci)
        c.font = body
        c.fill = note_f
        c.border = BORDER
        c.alignment = Alignment(horizontal="left", vertical="center", wrap_text=True)
    nl = ws.cell(r_note, 1, "미달 사유")
    nl.font = Font(name=KFONT, size=10, bold=True, color=NAVY)
    if nf >= 2:
        ws.merge_cells(start_row=r_note, start_column=1, end_row=r_note, end_column=nf)
    for wi, wname in enumerate(weeks):
        a = nf + wi * WEEK_N + 1
        ws.merge_cells(start_row=r_note, start_column=a,
                       end_row=r_note, end_column=a + WEEK_N - 1)
        txt = str((notes or {}).get(wname) or "").strip()
        if txt:
            ws.cell(r_note, a, txt)
    ws.merge_cells(start_row=r_note, start_column=c0, end_row=r_note, end_column=c0 + 1)
    ws.cell(r_note, c0, "— 계획을 못 채운 주에만 적으시면 됩니다")
    ws.cell(r_note, c0).font = Font(name=KFONT, size=9, color="94A3B8")
    ws.row_dimensions[r_note].height = 34

    # 구분은 적어 넣을 수도 있으니 목록을 달아 둔다 (새 모델 줄용).
    # 칸이 빠질 수 있으니 자리를 찾아서 붙인다 — 예전에는 'D' 로 박혀 있었다.
    _gi = next((i for i, c in enumerate(cols, start=1) if c[2] == "group"), None)
    if _gi:
        _gc = get_column_letter(_gi)
        dv = DataValidation(type="list", formula1='"양산,개발"', allow_blank=True)
        ws.add_data_validation(dv)
        dv.add("%s%d:%s%d" % (_gc, FIRST_ROW, _gc, FIRST_ROW + n_rows - 1))

    ws.freeze_panes = ws.cell(FIRST_ROW, nf + 1)
    ws.sheet_view.showGridLines = False

    # 인쇄 — 가로 한 장에 다 들어가게. 주차가 잘려 나가면 종이로 돌려보며
    # 적는 사람이 어느 주차인지 못 본다. 머리글 두 줄은 장마다 반복한다.
    ws.page_setup.orientation = "landscape"
    ws.page_setup.fitToWidth = 1
    ws.page_setup.fitToHeight = 0
    ws.sheet_properties.pageSetUpPr.fitToPage = True
    ws.print_title_rows = "%d:%d" % (HDR_TOP, HDR_SUB)
    ws.print_area = "A1:%s%d" % (get_column_letter(last), r_note)
    return ws


def _guide(wb, months, cols=None):
    g = wb.create_sheet("작성 안내")
    g.column_dimensions["A"].width = 16
    g.column_dimensions["B"].width = 92
    lines = [
        ("한 장 = 한 달", "시트 이름이 그 달입니다 (%s). 이름을 바꾸지 마세요 — "
                          "그 이름으로 어느 달인지 알아봅니다."
                          % " · ".join(months)),
        ("왼쪽 %d칸" % len(cols or FIXED),
         "%s입니다. 이미 채워져 있으면 그대로 두세요. "
         "이 칸으로 어느 모델인지 찾습니다. 고치면 다른 모델이 되거나 못 찾습니다."
         % "·".join(c[0] for c in (cols or FIXED))),
        ("계획 / 실적", "그 주차에 나갈 예정 수량과 실제로 나간 수량입니다. "
                        "계획은 앞 주차까지 미리 적어도 됩니다. 실적은 지난 주차만 채우면 됩니다."),
        ("빈 칸", "주차 칸이 **한 줄 전체** 비어 있으면 그 줄은 건너뜁니다 — "
                  "지금 값이 그대로 남습니다. 다만 그 줄에 숫자가 하나라도 있으면 "
                  "같은 줄의 빈 주차 칸은 0 으로 들어갑니다. 그래서 "
                  "**내려받은 파일을 그대로 쓰시는 게 안전합니다** — 지난 주차가 "
                  "이미 적혀 있어서 비는 칸이 없습니다."),
        ("월 합계", "수식입니다. 손대지 마세요."),
        ("새 모델", "목록 아래 빈 줄에 적으시면 됩니다. 파트넘버가 있으면 파트넘버로, "
                    "없으면 모델명으로 찾습니다. 어느 쪽도 없는 줄은 건너뜁니다."),
        ("미달 사유", "맨 아래 줄입니다. 계획을 못 채운 주에만 그 주 칸에 "
                        "한 줄 적으시면 됩니다 — 화면의 '계획 미달' 칸에 그대로 들어갑니다."),
        ("", ""),
        ("이 파일이 전부입니다", "판가·재료비·PO수량·실적수량도 이 표 안에 있습니다. "
                                 "모델 등록 양식을 따로 받을 일이 없습니다 — "
                                 "새 모델도 목록 아래 빈 줄에 적으시면 됩니다."),
        ("받은 그대로 올리기", "내려받은 파일에는 지금까지 올라간 숫자가 채워져 "
                               "있습니다. 이번 주 칸만 더 적어 그대로 올리시면 됩니다 — "
                               "이미 채워져 있던 숫자는 그대로 남습니다."),
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


def build_weekly_template(project_label="", sheets=None, models=None,
                          filled=False) -> bytes:
    """주차별 계획·실적 양식 바이트.

    sheets : [{"month": "2026-09", "weeks": ["W36", ...], "notes": {...}}, ...]
             — 시트 한 장씩. notes 는 {'W41': '미달 사유'}.
    models : 왼쪽 칸을 채울 모델 목록. 없으면 빈 줄만 둔다.
    filled : 주차 숫자와 미달 사유까지 채운다 (내보내기).
    """
    sheets = [s for s in (sheets or []) if isinstance(s, dict) and s.get("month")]
    if not sheets:
        raise ValueError("어느 달의 양식인지 알려 주세요")
    # 보드와 같은 순서로 — 유형끼리 모으고 그 안에서 이름순
    models = order_models(models or [])

    wb = Workbook()
    for i, s in enumerate(sheets):
        weeks = [str(w).strip().upper() for w in (s.get("weeks") or []) if str(w).strip()]
        if not weeks:
            raise ValueError("%s 의 주차 목록이 비었습니다" % s["month"])
        _sheet(wb, str(s["month"]), weeks, models, project_label, first=(i == 0),
               filled=filled, notes=s.get("notes") or {})
    _guide(wb, [str(s["month"]) for s in sheets], fixed_cols(models))

    buf = BytesIO()
    wb.save(buf)
    return buf.getvalue()
