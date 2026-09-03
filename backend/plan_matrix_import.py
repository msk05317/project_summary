"""'구분 x 주차' 형태의 출하/실적 엑셀 파서.

파워박스 '출하 및 실적' 시트처럼 아래 구조를 읽는다.

    구분 | PO수량 | 출하실적 | 잔량 | 6월(계획/실적) | 7월(계획/실적) |
         | 8월 [ W32(계획/실적) W33 ... ] | 8월 합계(계획/실적) | 9월(계획) ...
    AetherGDX  ...
    양산19종   ...
    합계       ...

열 위치는 고정하지 않고 '계획/실적' 하위 머리글과 병합된 월/주차 머리글로 찾는다.
"""

import re
import datetime as _dt

WEEK_RE = re.compile(r"^W\s*(\d{1,2})$", re.I)
MONTH_RE = re.compile(r"^(\d{1,2})\s*월")
TOTAL_LABELS = {"합계", "총계", "소계", "total", "sum"}


def _s(v):
    return "" if v is None else str(v).strip()


def _num(v):
    if v is None:
        return 0
    if isinstance(v, (int, float)):
        try:
            return int(round(v))
        except Exception:
            return 0
    t = str(v).strip().replace(",", "")
    if t in ("", "-", "N/A", "n/a", "없음"):
        return 0
    try:
        return int(round(float(t)))
    except Exception:
        return 0


def _filled_grid(ws):
    """병합 셀은 앵커 값을 범위 전체에 퍼뜨린 2차원 값 배열(1-based dict)."""
    grid = {}
    for r in range(1, ws.max_row + 1):
        for c in range(1, ws.max_column + 1):
            grid[(r, c)] = ws.cell(r, c).value
    for rng in ws.merged_cells.ranges:
        mc, mr, xc, xr = rng.bounds
        val = grid.get((mr, mc))
        for rr in range(mr, xr + 1):
            for cc in range(mc, xc + 1):
                grid[(rr, cc)] = val
    return grid


def _year_for_month(mon, today=None):
    today = today or _dt.date.today()
    y = today.year
    if mon - today.month > 6:
        y -= 1
    elif today.month - mon > 6:
        y += 1
    return y


def find_layout(ws, grid):
    """(하위머리글행, 라벨열, 주차쌍, 월쌍, 정보열) 반환."""
    sub_row = None
    for r in range(1, min(ws.max_row, 12) + 1):
        plans = sum(1 for c in range(1, ws.max_column + 1) if _s(grid.get((r, c))) == "계획")
        if plans >= 2:
            sub_row = r
            break
    if sub_row is None:
        return None

    # 라벨 열: 하위머리글 행 아래에서 텍스트가 있는 첫 열
    label_col = None
    for c in range(1, ws.max_column + 1):
        head = _s(grid.get((sub_row - 2, c))) + _s(grid.get((sub_row - 1, c))) + _s(grid.get((sub_row, c)))
        if head in ("구분", "모델", "모델명", "파트번호", "품명"):
            label_col = c
            break
    if label_col is None:
        for r in range(sub_row + 1, min(sub_row + 4, ws.max_row) + 1):
            for c in range(1, ws.max_column + 1):
                t = _s(grid.get((r, c)))
                if t and not t.replace(".", "").replace("-", "").isdigit():
                    label_col = c
                    break
            if label_col:
                break
    if label_col is None:
        return None

    # 정보 열 (PO수량 / 출하실적 / 잔량)
    info = {}
    for c in range(label_col + 1, ws.max_column + 1):
        head = " ".join(_s(grid.get((r, c))) for r in range(1, sub_row + 1))
        flat = head.replace("\n", "").replace(" ", "")
        if "PO수량" in flat and "po" not in info:
            info["po"] = c
        elif ("출하실적" in flat or flat == "실적") and "ship" not in info and c <= label_col + 3:
            info["ship"] = c
        elif "잔량" in flat and "rem" not in info:
            info["rem"] = c

    # 계획/실적 쌍 → 주차 or 월
    week_pairs, month_pairs = [], []
    c = label_col + 1
    while c <= ws.max_column:
        if _s(grid.get((sub_row, c))) != "계획":
            c += 1
            continue
        act_c = c + 1 if _s(grid.get((sub_row, c + 1))) == "실적" else None
        week, month_no, is_total = None, None, False
        for r in range(sub_row - 1, 0, -1):
            t = _s(grid.get((r, c)))
            if not t:
                continue
            m = WEEK_RE.match(t)
            if m and week is None:
                week = int(m.group(1))
                continue
            mm = MONTH_RE.match(t)
            if mm and month_no is None:
                month_no = int(mm.group(1))
                if "합계" in t or "total" in t.lower():
                    is_total = True
        if month_no is None:
            c = (act_c or c) + 1
            continue
        entry = (month_no, c, act_c)
        if week is not None:
            week_pairs.append((week,) + entry)
        elif not is_total:
            month_pairs.append(entry)
        c = (act_c or c) + 1

    return sub_row, label_col, week_pairs, month_pairs, info


def parse_plan_matrix(wb, sheet_name=None, today=None):
    ws = wb[sheet_name] if sheet_name and sheet_name in wb.sheetnames else None
    layout = None
    if ws is not None:
        grid = _filled_grid(ws)
        layout = find_layout(ws, grid)
    else:
        for name in wb.sheetnames:
            cand = wb[name]
            g = _filled_grid(cand)
            lay = find_layout(cand, g)
            if lay and lay[2]:
                ws, grid, layout = cand, g, lay
                break
    if ws is None or not layout or not layout[2]:
        return {"sheet": None, "rows": [], "total": None, "months": []}

    sub_row, label_col, week_pairs, month_pairs, info = layout

    rows, total = [], None
    months_seen = set()
    for r in range(sub_row + 1, ws.max_row + 1):
        label = _s(grid.get((r, label_col)))
        if not label or label == ".":
            continue

        weeks = {}
        for wno, mon, pc, ac in week_pairs:
            y = _year_for_month(mon, today)
            key = f"{y}-{mon:02d}"
            raw_p = ws.cell(r, pc).value
            raw_a = ws.cell(r, ac).value if ac else None
            if _s(raw_p) in ("", "-") and _s(raw_a) in ("", "-"):
                continue
            weeks.setdefault(key, {})[f"W{wno:02d}"] = {
                "plan": _num(raw_p), "actual": _num(raw_a)}
            months_seen.add(key)

        months = {}
        for mon, pc, ac in month_pairs:
            y = _year_for_month(mon, today)
            key = f"{y}-{mon:02d}"
            raw_p = ws.cell(r, pc).value
            raw_a = ws.cell(r, ac).value if ac else None
            if _s(raw_p) in ("", "-") and _s(raw_a) in ("", "-"):
                continue
            months[key] = {"plan": _num(raw_p), "actual": _num(raw_a)}
            months_seen.add(key)

        entry = {
            "label": label,
            "po_qty": _num(ws.cell(r, info["po"]).value) if info.get("po") else 0,
            "shipped_qty": _num(ws.cell(r, info["ship"]).value) if info.get("ship") else 0,
            "remaining": _num(ws.cell(r, info["rem"]).value) if info.get("rem") else 0,
            "weeks": weeks,
            "months": months,
        }
        if label.lower() in TOTAL_LABELS:
            total = entry
            break
        rows.append(entry)

    return {
        "sheet": ws.title,
        "rows": rows,
        "total": total,
        "months": sorted(months_seen),
    }
