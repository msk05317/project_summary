"""하바플레이트 주간 보고 엑셀(W##.xlsx) 파서.

한 시트 안에 아래 블록이 순서대로 들어 있는 구조를 읽는다.
  1. 현황            : 양산/개발 총계
  2. 양산모델        : 모델 / 소재 / 판가 / PO / 출하 / 잔량 / 재고 / 비고
  3~5. 개발품        : 모델 / 소재 / 판가 / 개발단계 / 개발종류(HVM·RPM) / PO / 출하 / 비고
  주차 매트릭스     : 파트번호별 월 실적 + 주차별 계획/실적 (W32~), 마지막에 total·개발 합계 행

열 위치는 고정하지 않고 '머리글 라벨'로 찾는다. 시트가 조금 바뀌어도 견디게 하기 위함.
"""

import re
import datetime as _dt

WEEK_RE = re.compile(r"^W\s*(\d{1,2})$", re.I)
MONTH_RE = re.compile(r"^(\d{1,2})\s*월")
SECTION_RE = re.compile(r"^\s*(\d)\s*\.\s*(.+)")


def _s(v):
    return "" if v is None else str(v).strip()


def _num(v):
    """'-', 'N/A', '' → 0. 소수는 반올림."""
    if v is None:
        return 0
    if isinstance(v, (int, float)):
        return int(round(v))
    t = str(v).strip().replace(",", "")
    if t in ("", "-", "N/A", "n/a", "없음"):
        return 0
    try:
        return int(round(float(t)))
    except Exception:
        return 0


def _price(v):
    if v is None:
        return 0
    try:
        return int(round(float(str(v).replace(",", ""))))
    except Exception:
        return 0


def _date_text(v):
    if v is None:
        return ""
    if isinstance(v, _dt.datetime):
        return v.date().isoformat()
    if isinstance(v, _dt.date):
        return v.isoformat()
    return str(v).strip()


def pick_sheet(wb, sheet_name=None):
    """W 번호가 가장 큰 시트를 정본으로 고른다."""
    if sheet_name and sheet_name in wb.sheetnames:
        return wb[sheet_name]
    best, best_n = None, -1
    for name in wb.sheetnames:
        m = WEEK_RE.match(name.strip())
        if m and int(m.group(1)) > best_n:
            best, best_n = name, int(m.group(1))
    return wb[best] if best else wb.worksheets[-1]


def _grid(ws, max_row=None, max_col=None):
    max_row = max_row or ws.max_row
    max_col = max_col or ws.max_column
    return [[ws.cell(row=r, column=c).value for c in range(1, max_col + 1)]
            for r in range(1, max_row + 1)]


def _find_header(grid, start_row, keys=("모델", "판가")):
    """start_row 아래에서 keys 를 모두 포함하는 머리글 행을 찾아 (행index, {라벨:열index}) 반환."""
    for r in range(start_row, min(start_row + 8, len(grid))):
        cells = [_s(v) for v in grid[r]]
        joined = " ".join(cells)
        if all(k in joined for k in keys):
            cols = {}
            for i, t in enumerate(cells):
                if t:
                    cols.setdefault(t, i)
            return r, cols
    return None, {}


def _col(cols, *names):
    """라벨 후보 중 먼저 맞는 열 index. 부분일치도 허용."""
    for n in names:
        if n in cols:
            return cols[n]
    for n in names:
        for label, idx in cols.items():
            if n in label:
                return idx
    return None


def _month_of_week(week_no, year):
    """ISO 주차 → 그 주 목요일이 속한 'YYYY-MM'."""
    try:
        thu = _dt.date.fromisocalendar(year, week_no, 4)
        return f"{thu.year}-{thu.month:02d}"
    except Exception:
        return None


def parse_workbook(wb, sheet_name=None, year=None):
    ws = pick_sheet(wb, sheet_name)
    grid = _grid(ws)
    year = year or _dt.date.today().year

    sections = {}          # 번호 → 시작 행 index
    matrix_row = None      # '파트번호' 머리글 행 index
    for r, row in enumerate(grid):
        for v in row[:4]:
            m = SECTION_RE.match(_s(v))
            if m:
                sections.setdefault(int(m.group(1)), r)
        if matrix_row is None and any(_s(v) == "파트번호" for v in row):
            matrix_row = r

    models = []
    seen = set()

    def _read_model_block(sec_no, group):
        start = sections.get(sec_no)
        if start is None:
            return
        hr, cols = _find_header(grid, start + 1)
        if hr is None:
            return
        c_model = _col(cols, "모델", "파트번호")
        if c_model is None:
            return
        c_price = _col(cols, "판가")
        c_po = _col(cols, "PO 수량", "PO수량")
        c_ship = _col(cols, "출하수량", "출하실적", "출하 수량")
        c_note = _col(cols, "비고")
        c_mat = _col(cols, "소재")
        c_devkind = _col(cols, "개발종류")
        c_devstage = _col(cols, "개발단계")
        c_due = _col(cols, "고객요청일", "제출일", "LAIR ECD")
        c_done = _col(cols, "가공 완료", "가공완료")

        for r in range(hr + 1, len(grid)):
            row = grid[r]
            mid = _s(row[c_model]) if c_model < len(row) else ""
            if not mid:
                if r + 1 < len(grid) and not _s(grid[r + 1][c_model] if c_model < len(grid[r + 1]) else ""):
                    break
                continue
            if mid.lower() in ("total", "합계", "소계", "."):
                break
            if SECTION_RE.match(mid):
                break
            if mid in seen:
                continue
            seen.add(mid)

            note_parts = []
            if c_note is not None and c_note < len(row) and _s(row[c_note]):
                note_parts.append(_s(row[c_note]))
                for extra in range(c_note + 1, min(c_note + 3, len(row))):
                    t = _s(row[extra])
                    if t and not t.replace(".", "").isdigit():
                        note_parts.append(t)
            if c_devstage is not None and c_devstage < len(row) and _s(row[c_devstage]):
                note_parts.insert(0, f"[{_s(row[c_devstage])}]")
            if c_due is not None and c_due < len(row) and _date_text(row[c_due]):
                note_parts.append(f"요청일 {_date_text(row[c_due])}")
            if c_done is not None and c_done < len(row) and _date_text(row[c_done]):
                note_parts.append(f"가공완료 {_date_text(row[c_done])}")

            dev_type = ""
            if c_devkind is not None and c_devkind < len(row):
                dev_type = _s(row[c_devkind]).upper()

            models.append({
                "id": mid,
                "name": mid,
                "group": group,
                "price": _price(row[c_price]) if c_price is not None and c_price < len(row) else 0,
                "po_qty": _num(row[c_po]) if c_po is not None and c_po < len(row) else 0,
                "shipped_qty": _num(row[c_ship]) if c_ship is not None and c_ship < len(row) else 0,
                "note": " · ".join(note_parts),
                "material": _s(row[c_mat]) if c_mat is not None and c_mat < len(row) else "",
                "dev_type": dev_type if group == "개발" else "",
            })

    _read_model_block(2, "양산")
    for sec in (3, 4, 5):
        _read_model_block(sec, "개발")

    # ── 주차 매트릭스 ──
    weekly = {}
    monthly = {}
    summary = {}
    if matrix_row is not None:
        head = grid[matrix_row]
        week_row = grid[matrix_row + 1] if matrix_row + 1 < len(grid) else []
        kind_row = grid[matrix_row + 2] if matrix_row + 2 < len(grid) else []

        c_model = next((i for i, v in enumerate(head) if _s(v) == "파트번호"), 2)
        c_po = next((i for i, v in enumerate(head) if "PO 수량" in _s(v)), None)
        c_ship = next((i for i, v in enumerate(head) if "출하실적" in _s(v)), None)
        c_rem = next((i for i, v in enumerate(head) if "PO 잔량" in _s(v)), None)

        week_cols = []
        for i, v in enumerate(week_row):
            m = WEEK_RE.match(_s(v))
            if not m:
                continue
            wno = int(m.group(1))
            plan_c, act_c = i, i + 1
            if _s(kind_row[i] if i < len(kind_row) else "") == "실적":
                plan_c, act_c = i - 1, i
            week_cols.append((wno, plan_c, act_c))

        used = {c for _, p, a in week_cols for c in (p, a)}
        month_cols = []
        for i, v in enumerate(head):
            m = MONTH_RE.match(_s(v))
            if m and i not in used and _s(kind_row[i] if i < len(kind_row) else "") == "실적":
                month_cols.append((int(m.group(1)), i))

        cur_month = _dt.date.today().month
        for r in range(matrix_row + 3, len(grid)):
            row = grid[r]
            mid = _s(row[c_model]) if c_model < len(row) else ""
            low = mid.lower()
            if not mid or mid == ".":
                continue
            if low in ("total", "합계") or mid.startswith("개발"):
                label = "양산" if low in ("total", "합계") else "개발"
                weeks = {}
                for wno, pc, ac in week_cols:
                    weeks[f"W{wno:02d}"] = {
                        "plan": _num(row[pc]) if pc < len(row) else 0,
                        "actual": _num(row[ac]) if ac < len(row) else 0,
                    }
                summary[label] = {
                    "po_qty": _num(row[c_po]) if c_po is not None and c_po < len(row) else 0,
                    "actual_total": _num(row[c_ship]) if c_ship is not None and c_ship < len(row) else 0,
                    "remaining": _num(row[c_rem]) if c_rem is not None and c_rem < len(row) else 0,
                    "weeks": weeks,
                }
                if label == "개발":
                    break
                continue

            wmap = {}
            for wno, pc, ac in week_cols:
                month = _month_of_week(wno, year)
                if not month:
                    continue
                wmap.setdefault(month, {})[f"W{wno:02d}"] = {
                    "plan": _num(row[pc]) if pc < len(row) else 0,
                    "actual": _num(row[ac]) if ac < len(row) else 0,
                }
            if wmap:
                weekly[mid] = wmap

            mm = {}
            for mon, ci in month_cols:
                y = year if mon <= cur_month else year - 1
                mm[f"{y}-{mon:02d}"] = _num(row[ci]) if ci < len(row) else 0
            if mm:
                monthly[mid] = mm

    for m in models:
        if m["id"] in weekly:
            m["weekly_plan"] = weekly[m["id"]]
        if m["id"] in monthly:
            m["monthly_actual"] = monthly[m["id"]]

    if summary.get("개발"):
        summary["개발"]["price_fixed"] = 3400

    return {
        "sheet": ws.title,
        "models": models,
        "weekly_summary": summary,
        "counts": {
            "양산": sum(1 for m in models if m["group"] == "양산"),
            "개발": sum(1 for m in models if m["group"] == "개발"),
            "주차데이터": len(weekly),
            "월실적": len(monthly),
        },
    }
