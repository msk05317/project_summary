# 사업부 매출 — 엑셀이 원본이다.
#
# 모델 판가 × 수량으로 매출을 계산하던 것을 그만둔다. 판가는 추정이고,
# 실제로 하바플레이트 55종 중 52종이 3,400 으로 일괄 입력돼 있어서 9월
# 매출이 18만 달러 부풀어 있었다. 확정 금액은 이미 엑셀에 있다.
#
#   실적 = 일일보고 (DAILY)      매일 만드는 파일. W## 시트마다 날짜별 금액.
#   계획 = 월 매출 계획           Estimate Revenue in Sep · Sum 시트.
#
# 실적을 '날짜' 로 저장하는 이유: 엑셀은 9월을 W36~W39 로 보고 OneView 는
# W36~W40 으로 봐서 한 주가 통째로 어긋났다. 날짜로 두면 달의 경계를
# 약속할 필요가 없다 — 9월 매출은 9월 날짜의 합이다.
import datetime as _dt
import io
import json
import re

# 엑셀 행 이름 → 품목. 이름이 바뀌면 '모르는 항목' 으로 올라와서
# 사람이 한 번 연결해 준다. 조용히 빠뜨리지 않는다.
DEFAULT_MAP = {
    # ── 월 계획 (Sum 시트)
    "Cable Internal": "케이블 (사내)",
    "Metal": "메탈 가공",
    "PBX": "파워박스",
    "Major Modules": "메이저 모듈",
    "Sheet metal": "시트메탈 · 프레임",
    "Frame": "시트메탈 · 프레임",
    "Data Center": "데이터센터",
    "Plastic": "플라스틱 가공",
    "Cable LAM": "케이블 (LAM)",
    "Hwaseong Sheet metal": "화성 시트메탈",
    "Gumi Sheet Metal": "구미 시트메탈",
    "EMA": "EMA",
    "Hwaseong MCT": "화성 MCT",
    "Space X": "Space X",
    "Gumi MCT": "구미 MCT",
    # ── 일일보고 (W## 시트)
    #    엔클로저는 계획 파일에 따로 없고 Metal 안에 들어 있다.
    "메탈 가공 (Metal Machining)": "메탈 가공",
    "엔클로져 (Encloser)": "메탈 가공",
    "캐스팅 (Casting)": "메탈 가공",
    "플라스틱 가공 (Plastic Machining)": "플라스틱 가공",
    "Lam + others (Cable Direct)": "케이블 (LAM)",
    "LAM PCB": "케이블 (LAM)",
    "시트메탈 (Sheetmetal Direct) / 프레임 (Frame Direct)": "시트메탈 · 프레임",
    "메이저 모듈 (Major Module)": "메이저 모듈",
    "파워박스 (Powerbox)": "파워박스",
    "Texon 구미 전체 - Gumi SM": "구미 시트메탈",
    "Texon 구미 전체 - Gumi MCT": "구미 MCT",
    "Texon 화성 전체 - Hwaseong ( Machining)": "화성 MCT",
    "Texon 화성 전체 - Hwaseong (SM / FR)": "화성 시트메탈",
    "Texon 구미 전체 - Gumi Cable": "케이블 (사내)",
    "Texon 화성 전체 - Hwaseong cable": "케이블 (사내)",
    "Texon 미국 전체 - USA Cable": "케이블 (사내)",
    "Texon - YONGIN Cable": "케이블 (사내)",
    # 연초에 쓰던 옛 이름들. 같은 줄인데 이름만 바뀌었다.
    "케이블 (Cable Direct)": "케이블 (LAM)",
    "Texon 구미 전체 - Gumi SM / Machining": "구미 시트메탈",
    "Texon 화성 전체 - Hwaseong (SM / Machining/ FR)": "화성 시트메탈",
}

# 계획 파일에 나오는 순서. 표는 계획 큰 것부터 그리므로 참고용이다.
ITEM_ORDER = ["케이블 (사내)", "메탈 가공", "파워박스", "메이저 모듈",
              "시트메탈 · 프레임", "데이터센터", "플라스틱 가공", "케이블 (LAM)",
              "화성 시트메탈", "구미 시트메탈", "EMA", "화성 MCT",
              "Space X", "구미 MCT"]

_MONTHS = {"jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
           "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12}


def norm(s) -> str:
    """줄바꿈·겹공백을 없앤 이름. 엑셀은 같은 줄을 파일마다 다르게 접는다."""
    return " ".join(str(s or "").split())


def blank() -> dict:
    return {"version": 1, "updated_at": None, "map": dict(DEFAULT_MAP),
            "days": {}, "plans": {}, "sources": {}}


def load(path) -> dict:
    try:
        with open(path, "r", encoding="utf-8") as f:
            d = json.load(f)
        if not isinstance(d, dict):
            return blank()
    except Exception:
        return blank()
    base = blank()
    for k, v in base.items():
        d.setdefault(k, v)
    # 기본 매핑은 항상 깔고, 사람이 고친 값이 위에 온다
    m = dict(DEFAULT_MAP)
    m.update({norm(k): v for k, v in (d.get("map") or {}).items() if v})
    d["map"] = m
    return d


def save(path, store: dict) -> None:
    store["updated_at"] = _dt.datetime.now().isoformat(timespec="seconds")
    tmp = str(path) + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(store, f, ensure_ascii=False, indent=1)
    import os
    os.replace(tmp, path)


def _num(v) -> float:
    if v is None or v == "":
        return 0.0
    if isinstance(v, (int, float)):
        return float(v)
    try:
        return float(str(v).replace(",", "").strip())
    except Exception:
        return 0.0


def _open(raw: bytes):
    import openpyxl
    try:
        # 글꼴 family 가 14 를 넘는 파일이 있다. openpyxl 이 그대로 죽는다.
        from openpyxl.styles.fonts import Font
        Font.family.max = 1000
    except Exception:
        pass
    return openpyxl.load_workbook(io.BytesIO(raw), data_only=True)


def _year_for(week: int, mm: int, dd: int, hint: int = None) -> int:
    """W37 시트의 '09 / 07' 이 몇 년인지.

    파일의 해를 그대로 쓴다. 주차로 되짚으면 안 된다 — W35 시트에 08/31
    이 들어 있는데 그 날의 ISO 주차는 36 이라, 35 에 맞는 해(2025)로
    밀려난다. 연말연시만 예외다: 12월 보드의 W01 은 다음 해, 1월 보드의
    W52 는 지난 해.
    """
    y = hint or _dt.date.today().year
    if mm == 12 and week <= 2:
        y += 1
    elif mm == 1 and week >= 52:
        y -= 1
    try:
        _dt.date(y, mm, dd)
    except ValueError:
        return hint or _dt.date.today().year
    return y


def parse_daily(raw: bytes, year_hint: int = None) -> dict:
    """일일보고에서 날짜별 금액을 꺼낸다.

    시트 이름이 W## 인 것만 본다. 각 시트 머리에 '09 / 07' 같은 날짜가 있고
    그 아래 Plan / Q'ty / Amount 세 칸이 붙는다.
    """
    wb = _open(raw)
    days, rows, sheets = {}, [], []
    for ws in wb.worksheets:
        m = re.fullmatch(r"W(\d{1,2})", str(ws.title).strip())
        if not m or ws.sheet_state != "visible":
            continue
        week = int(m.group(1))
        grid = list(ws.iter_rows(values_only=True))
        # 날짜가 적힌 머리 줄 찾기
        hi, cols = -1, []
        for i, r in enumerate(grid[:6]):
            got = []
            for j, v in enumerate(r):
                d = re.fullmatch(r"(\d{1,2})\s*/\s*(\d{1,2})", norm(v))
                if d:
                    got.append((j, int(d.group(1)), int(d.group(2))))
            if got:
                hi, cols = i, got
                break
        if hi < 0:
            continue
        sheets.append(ws.title)
        # 날짜 한 칸이 늘 Plan · Q'ty · Amount 세 칸인 건 아니다. W9 처럼
        # 'Plan ($) update' 가 끼어드는 주가 있어서, 아랫줄 이름으로 찾는다.
        sub = grid[hi + 1] if len(grid) > hi + 1 else ()
        stop = len(sub)
        for j, v in enumerate(grid[hi]):
            if v and "total" in str(v).lower():
                stop = min(stop, j) if j > (cols[-1][0] if cols else 0) else stop
        picks = []
        for n, (j, mm, dd) in enumerate(cols):
            end = cols[n + 1][0] if n + 1 < len(cols) else stop
            pj = qj = aj = None
            for k in range(j, min(end, len(sub))):
                lab = norm(sub[k]).lower()
                if aj is None and lab.startswith("amount"):
                    aj = k
                elif qj is None and lab.startswith("q'ty"):
                    qj = k
                elif pj is None and lab.startswith("plan"):
                    pj = k
            picks.append((mm, dd,
                          j if pj is None else pj,
                          j + 1 if qj is None else qj,
                          j + 2 if aj is None else aj))
        for r in grid[hi + 2:]:
            lab = norm(r[1] if len(r) > 1 else "")
            if not lab or lab.startswith("총합계"):
                continue
            if lab not in rows:
                rows.append(lab)
            for mm, dd, pj, qj, aj in picks:
                if aj >= len(r):
                    continue
                plan = _num(r[pj]) if pj < len(r) else 0.0
                qty = _num(r[qj]) if qj < len(r) else 0.0
                amt = _num(r[aj])
                if not (plan or qty or amt):
                    continue
                y = _year_for(week, mm, dd, year_hint)
                key = "%04d-%02d-%02d" % (y, mm, dd)
                cell = days.setdefault(key, {}).setdefault(
                    lab, {"plan": 0.0, "qty": 0.0, "amount": 0.0})
                cell["plan"] += plan
                cell["qty"] += qty
                cell["amount"] += amt
    return {"days": days, "rows": rows, "sheets": sheets}


def _month_from_text(*texts) -> str:
    joined = " ".join(str(t or "") for t in texts)
    m = re.search(r"(20\d\d)[-/\.](\d{1,2})", joined)
    if m:
        return "%s-%02d" % (m.group(1), int(m.group(2)))
    m = re.search(r"(\d{1,2})\s*월", joined)
    mm = int(m.group(1)) if m else 0
    if not mm:
        for name, num in _MONTHS.items():
            if re.search(r"\b" + name, joined, re.I):
                mm = num
                break
    if not mm:
        return ""
    y = _dt.date.today().year
    return "%04d-%02d" % (y, mm)


def parse_plan(raw: bytes, filename: str = "") -> dict:
    """월 계획에서 품목별 금액을 꺼낸다 (Sum 시트, 두 칸짜리 표)."""
    wb = _open(raw)
    ws = wb["Sum"] if "Sum" in wb.sheetnames else wb.worksheets[0]
    items, order, month = {}, [], ""
    for r in ws.iter_rows(values_only=True):
        a = norm(r[0] if len(r) > 0 else "")
        b = r[1] if len(r) > 1 else None
        if not a:
            continue
        if a.lower().startswith("commodity"):
            month = _month_from_text(b, filename)
            continue
        if a.lower() in ("total", "합계", "sum"):
            continue
        if not isinstance(b, (int, float)):
            continue
        items[a] = float(b)
        order.append(a)
    if not month:
        month = _month_from_text(filename) or _dt.date.today().strftime("%Y-%m")
    return {"month": month, "items": items, "order": order}


def unknown_rows(store: dict, labels) -> list:
    """매핑에 없는 엑셀 행. 금액이 있는 것만 물어본다."""
    m = store.get("map") or {}
    return [x for x in labels if norm(x) not in m]


def unmapped_in_store(store: dict) -> list:
    """저장된 실적 중 아직 어느 품목에도 안 붙은 행. 금액 큰 것부터."""
    m = store.get("map") or {}
    got = {}
    for rowmap in (store.get("days") or {}).values():
        for lab, cell in (rowmap or {}).items():
            if norm(lab) in m:
                continue
            got[norm(lab)] = got.get(norm(lab), 0.0) + float(
                (cell or {}).get("amount") or 0)
    out = [{"label": k, "amount": round(v)} for k, v in got.items()]
    out.sort(key=lambda x: -x["amount"])
    return out


def items_of(store: dict) -> list:
    """지금 쓰이는 품목 이름들 (연결 대상 후보)."""
    seen = []
    for name in ITEM_ORDER:
        seen.append(name)
    for v in (store.get("map") or {}).values():
        if v and v not in seen:
            seen.append(v)
    return seen


def apply_daily(store: dict, parsed: dict, filename: str = "") -> dict:
    """읽은 날짜만 갈아 끼운다. 같은 파일을 두 번 올려도 더해지지 않는다."""
    days = store.setdefault("days", {})
    before = _sum_all(days)
    for day, rowmap in (parsed.get("days") or {}).items():
        days[day] = rowmap
    store.setdefault("sources", {})["daily"] = {
        "file": filename,
        "at": _dt.datetime.now().isoformat(timespec="seconds"),
        "sheets": parsed.get("sheets") or [],
        "days": len(parsed.get("days") or {}),
    }
    return {"before": before, "after": _sum_all(days),
            "days": sorted(parsed.get("days") or {})}


def apply_plan(store: dict, parsed: dict, filename: str = "",
               month: str = "") -> dict:
    month = month or parsed.get("month") or ""
    plans = store.setdefault("plans", {})
    before = sum((plans.get(month) or {}).values())
    plans[month] = dict(parsed.get("items") or {})
    store.setdefault("sources", {})["plan"] = {
        "file": filename,
        "at": _dt.datetime.now().isoformat(timespec="seconds"),
        "month": month,
    }
    return {"month": month, "before": before,
            "after": sum(plans[month].values())}


def _sum_all(days: dict) -> float:
    t = 0.0
    for rowmap in (days or {}).values():
        for cell in (rowmap or {}).values():
            t += float((cell or {}).get("amount") or 0)
    return t


def _fold(store: dict, rowmap: dict, out: dict) -> None:
    m = store.get("map") or {}
    for lab, cell in (rowmap or {}).items():
        item = m.get(norm(lab))
        if not item:
            continue                      # 연결 안 한 행은 합계에서 뺀다
        o = out.setdefault(item, {"amount": 0.0, "qty": 0.0})
        o["amount"] += float((cell or {}).get("amount") or 0)
        o["qty"] += float((cell or {}).get("qty") or 0)


def month_view(store: dict, month: str) -> dict:
    """그 달의 품목별 계획·실적. 홈 매출 카드와 admin 표가 같이 쓴다."""
    days = store.get("days") or {}
    plans = (store.get("plans") or {}).get(month) or {}
    m = store.get("map") or {}

    act = {}
    last_day = ""
    for day, rowmap in days.items():
        if not str(day).startswith(month):
            continue
        _fold(store, rowmap, act)
        # 앞으로의 날짜에는 계획만 적혀 있다. 기준일은 실적이 들어온 날까지.
        if day > last_day and any(
                float((c or {}).get("amount") or 0) for c in (rowmap or {}).values()):
            last_day = day

    plan_item = {}
    for lab, amt in plans.items():
        item = m.get(norm(lab))
        if not item:
            continue
        plan_item[item] = plan_item.get(item, 0.0) + float(amt or 0)

    names = set(plan_item) | set(act)
    rows = []
    for it in names:
        p = round(plan_item.get(it, 0.0))
        a = round((act.get(it) or {}).get("amount", 0.0))
        rows.append({"item": it, "plan": p, "actual": a,
                     "qty": round((act.get(it) or {}).get("qty", 0.0)),
                     "rate": round(a * 100 / p) if p > 0 else None})
    rows.sort(key=lambda r: (-r["plan"], -r["actual"], r["item"]))

    tp = sum(r["plan"] for r in rows)
    ta = sum(r["actual"] for r in rows)
    year = month[:4]
    ytd = 0.0
    for day, rowmap in days.items():
        if not str(day).startswith(year):
            continue
        one = {}
        _fold(store, rowmap, one)
        ytd += sum(v["amount"] for v in one.values())
    return {
        "month": month, "items": rows,
        "plan": tp, "actual": ta,
        "rate": round(ta * 100 / tp) if tp > 0 else None,
        "left": max(0, tp - ta),
        "ytd": round(ytd),
        "as_of": last_day,
        "has_data": bool(rows),
        "sources": store.get("sources") or {},
    }
