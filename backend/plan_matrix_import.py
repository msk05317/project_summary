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
# 사이트(공장) 표기 → 모델명 접미사
SITE_ALIAS = {"화성": "HS", "HS": "HS", "VN": "VN", "베트남": "VN",
              "천안": "CA", "아산": "AS", "평택": "PT"}
# 개별 모델이 아니라 묶음(집계) 행으로 볼 라벨
AGG_RE = re.compile(r"(\d+\s*종|^양산|^개발|^EMA\s*양산)")


def _clean_label(t):
    """'CEFEM BE\n재고: 79' → ('CEFEM BE', 79)"""
    t = _s(t)
    if not t:
        return "", None
    stock = None
    m = re.search(r"재고\s*[:：]\s*(\d+)", t)
    if m:
        try:
            stock = int(m.group(1))
        except Exception:
            stock = None
    head = t.split("\n")[0].strip()
    head = re.sub(r"재고\s*[:：].*$", "", head).strip()
    return head, stock


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


def _month_of_week_iso(wno, year):
    """ISO 주차 번호 → 그 주 목요일이 속한 'YYYY-MM'. 주차 번호가 정본."""
    try:
        thu = _dt.date.fromisocalendar(year, wno, 4)
        return f"{thu.year}-{thu.month:02d}"
    except Exception:
        return None


def _year_for_month(mon, today=None):
    today = today or _dt.date.today()
    y = today.year
    if not mon:
        return y
    if mon - today.month > 6:
        y -= 1
    elif today.month - mon > 6:
        y += 1
    return y


def find_layout(ws, grid):
    """(하위머리글행, 라벨열, 주차쌍, 월쌍, 정보열, 사이트열) 반환."""
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

    # 사이트(공장) 열: 라벨 바로 오른쪽에 머리글 없이 '화성/VN' 같은 텍스트만 있는 열
    site_col = None
    c2 = label_col + 1
    if c2 <= ws.max_column:
        head2 = "".join(_s(grid.get((r, c2))) for r in range(1, sub_row + 1)).strip()
        if not head2:
            vals = [_s(grid.get((r, c2)))
                    for r in range(sub_row + 1, min(sub_row + 8, ws.max_row) + 1)]
            vals = [v for v in vals if v]
            if vals and all(not v.replace(".", "").replace("-", "").isdigit() for v in vals):
                site_col = c2

    # 정보 열 (PO수량 / 출하실적 / 잔량)
    info = {}
    for c in range((site_col or label_col) + 1, ws.max_column + 1):
        # 병합 머리글은 같은 값이 여러 행에 반복되므로 중복을 제거하고 본다
        uniq = []
        for r in range(1, sub_row + 1):
            t = _s(grid.get((r, c)))
            if t and t not in uniq:
                uniq.append(t)
        flat = " ".join(uniq).replace("\n", "").replace(" ", "")
        near = c <= (site_col or label_col) + 4
        if "PO수량" in flat and "po" not in info:
            info["po"] = c
        elif ("출하실적" in flat or flat in ("실적", "출하수량")) and "ship" not in info and near:
            info["ship"] = c
        elif "잔량" in flat and "rem" not in info:
            info["rem"] = c

    # 계획/실적 쌍 → 주차 or 월
    week_pairs, month_pairs = [], []
    c = (site_col or label_col) + 1
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
            if week is None:
                # 월도 주차도 못 찾은 열은 건너뛴다
                c = (act_c or c) + 1
                continue
            # 주차 열은 월 머리글이 없어도 주차 번호로 월을 정한다
            month_no = 0
        entry = (month_no, c, act_c)
        if week is not None:
            week_pairs.append((week,) + entry)
        elif not is_total:
            month_pairs.append(entry)
        c = (act_c or c) + 1

    return sub_row, label_col, week_pairs, month_pairs, info, site_col


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

    sub_row, label_col, week_pairs, month_pairs, info, site_col = layout

    rows, total = [], None
    months_seen = set()
    for r in range(sub_row + 1, ws.max_row + 1):
        base, stock = _clean_label(grid.get((r, label_col)))
        if not base or base == ".":
            continue
        site = _s(grid.get((r, site_col))) if site_col else ""
        label = f"{base}({SITE_ALIAS.get(site, site)})" if site else base

        weeks = {}
        for wno, mon, pc, ac in week_pairs:
            y = _year_for_month(mon, today)
            # 월 머리글(병합 밴드)이 없거나 어긋나도 주차 번호가 정본이다.
            # W32~W35 는 언제나 8월로 들어간다.
            key = _month_of_week_iso(wno, y) or f"{y}-{mon:02d}"
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
            "base_label": base,
            "site": site,
            "stock": stock,
            "is_aggregate": bool(AGG_RE.search(base)),
            "po_qty": _num(ws.cell(r, info["po"]).value) if info.get("po") else 0,
            "shipped_qty": _num(ws.cell(r, info["ship"]).value) if info.get("ship") else 0,
            "remaining": _num(ws.cell(r, info["rem"]).value) if info.get("rem") else 0,
            "weeks": weeks,
            "months": months,
        }
        if base.lower() in TOTAL_LABELS:
            total = entry
            break
        rows.append(entry)

    return {
        "sheet": ws.title,
        "rows": rows,
        "total": total,
        "months": sorted(months_seen),
    }
