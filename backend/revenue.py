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
import threading as _threading
import json
import re

# 엑셀 행 이름 → 품목. 이름이 바뀌면 '모르는 항목' 으로 올라와서
# 사람이 한 번 연결해 준다. 조용히 빠뜨리지 않는다.
DEFAULT_MAP = {
    # ── 일일보고 (W## 시트) — 한 줄이 한 품목이다
    "메탈 가공 (Metal Machining)": "메탈 가공",
    "엔클로져 (Encloser)": "엔클로져",
    "플라스틱 가공 (Plastic Machining)": "플라스틱 가공",
    "캐스팅 (Casting)": "캐스팅",
    "Lam + others (Cable Direct)": "Lam + others",
    "케이블 (Cable Direct)": "Lam + others",              # 연초 이름
    "LAM PCB": "LAM PCB",
    "시트메탈 (Sheetmetal Direct) / 프레임 (Frame Direct)": "시트메탈 / 프레임",
    "메이저 모듈 (Major Module)": "메이저모듈",
    "파워박스 (Powerbox)": "파워박스",
    "EMA": "EMA",
    "UCT (SM)": "UCT",
    "CELESTICA (SM/Frame)": "CELESTICA",
    "AVALON (SM)": "AVALON",
    "AVALON (SM/Machining)": "AVALON",                    # 연초 이름
    "Cleaning": "Cleaning",
    "Surface Treatment": "표면처리",
    "Data Center": "Data Center",
    "Space X": "Space X",
    "Texon 구미 전체 - Gumi SM": "구미 시트메탈",
    "Texon 구미 전체 - Gumi SM / Machining": "구미 시트메탈",   # 연초 이름
    "Texon 구미 전체 - Gumi MCT": "구미 MCT",
    "Texon 화성 전체 - Hwaseong ( Machining)": "화성 머시닝",
    "Texon - YONGIN (Machining)": "용인 머시닝",
    "Texon - YONGIN (SM/Machining)": "용인 머시닝",            # 연초 이름
    "Texon 화성 전체 - Hwaseong (SM / FR)": "화성 시트메탈 / 프레임",
    "Texon 화성 전체 - Hwaseong (SM / Machining/ FR)": "화성 시트메탈 / 프레임",
    "Texon 구미 전체 - Gumi Cable": "구미 케이블",
    "Texon 화성 전체 - Hwaseong cable": "화성 케이블",
    "Texon 미국 전체 - USA Cable": "USA 케이블",
    "Texon - YONGIN Cable": "용인 케이블",

    # ── 월 계획 (Sum 시트). 계획은 일일보고보다 굵어서 한 줄이 여러
    #    품목을 덮는다. 대표 품목에 붙이고 어디까지 덮는지 적어 둔다.
    "Metal": "메탈 가공",
    "Plastic": "플라스틱 가공",
    "Cable LAM": "Lam + others",
    "Sheet metal": "시트메탈 / 프레임",
    "Frame": "시트메탈 / 프레임",
    "Major Modules": "메이저모듈",
    "PBX": "파워박스",
    "Gumi Sheet Metal": "구미 시트메탈",
    "Gumi MCT": "구미 MCT",
    "Hwaseong MCT": "화성 머시닝",
    "Hwaseong Sheet metal": "화성 시트메탈 / 프레임",
    "Cable Internal": "구미 케이블",
}

# 계획 한 줄이 덮는 다른 품목들. 표에서 '계획 $0' 으로 보이는 이유다.
PLAN_COVERS = {
    "메탈 가공": ["엔클로져", "캐스팅"],
    "Lam + others": ["LAM PCB"],
    "구미 케이블": ["화성 케이블", "USA 케이블", "용인 케이블"],
}

# 보고서에 적히는 순서. 표도 이 순서로 그린다.
ITEM_ORDER = [
    "메탈 가공", "엔클로져", "플라스틱 가공", "캐스팅", "Lam + others",
    "LAM PCB", "시트메탈 / 프레임", "메이저모듈", "파워박스", "EMA",
    "UCT", "CELESTICA", "AVALON", "Cleaning", "표면처리",
    "Data Center",
    "Space X",
    "구미 시트메탈", "구미 MCT", "화성 머시닝", "용인 머시닝",
    "화성 시트메탈 / 프레임", "구미 케이블", "화성 케이블", "USA 케이블",
    "용인 케이블",
]

# 보고서 묶음.
#
#   매출합계 (Revenue)    반도체 / 데이터 센터 / 우주항공  → 소계
#   내부거래 (Internal)   구미/화성/미국/용인
#   총합 (내부거래 포함) = 소계 + 내부거래
#
# 내부거래는 텍슨 사이트(구미 · 화성 · 용인 · 미국)끼리 오간 것이다.
# UCT · CELESTICA · AVALON 은 바깥 고객이라 반도체 쪽이다.
#
# 한 줄은 한 쪽에만 들어간다. 양쪽에 넣으면 총합에서 두 번 세어져
# 일일보고 총합계와 안 맞는다.
GROUPS = [("semi", "반도체 (SEMI)"),
          ("dc", "데이터 센터 (Data Center)"),
          ("space", "우주항공 (Space X)")]
INTERNAL = ("internal", "구미/화성/미국 (Gumi/Hwaseong/USA/YONGIN)")

_INTERNAL_ITEMS = ("구미 시트메탈", "구미 MCT", "화성 머시닝", "용인 머시닝",
                   "화성 시트메탈 / 프레임", "구미 케이블", "화성 케이블",
                   "USA 케이블", "용인 케이블")

ITEM_GROUP = {}
for _it in ITEM_ORDER:
    ITEM_GROUP[_it] = ("internal" if _it in _INTERNAL_ITEMS
                       else "dc" if _it == "Data Center"
                       else "space" if _it == "Space X"
                       else "semi")


def group_of(item: str) -> str:
    """모르는 품목은 반도체로 본다 — 총합에서 빠지는 것보단 낫다."""
    return ITEM_GROUP.get(item, "semi")


_MONTHS = {"jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
           "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12}


def norm(s) -> str:
    """줄바꿈·겹공백을 없앤 이름. 엑셀은 같은 줄을 파일마다 다르게 접는다."""
    return " ".join(str(s or "").split())


def blank() -> dict:
    return {"version": 1, "updated_at": None, "map": dict(DEFAULT_MAP),
            "days": {}, "plans": {}, "sources": {}}


class RevenueFileBroken(Exception):
    """파일이 있는데 못 읽는다. 빈 값으로 갈아엎으면 안 된다."""


def _merge_map(raw: dict) -> dict:
    """기본 매핑 + 사람이 고친 것.

    값이 비어 있으면 '일부러 끊었다' 는 뜻이라 기본 매핑에서도 지운다.
    안 그러면 끊어도 새로고침하면 되살아난다.
    """
    m = dict(DEFAULT_MAP)
    for k, v in (raw or {}).items():
        k = norm(k)
        if not k:
            continue
        if v:
            m[k] = str(v)
        else:
            m.pop(k, None)
    return m


def load(path):
    """없으면 빈 것, 깨졌으면 예외.

    깨진 걸 빈 것으로 돌려주면 다음 저장이 멀쩡한 파일을 빈 값으로
    덮어쓴다. 한 번 그러면 되돌릴 방법이 없다.
    """
    import os
    if not os.path.exists(path):
        return blank()
    try:
        with open(path, "r", encoding="utf-8") as f:
            d = json.load(f)
    except Exception as e:
        raise RevenueFileBroken(str(e))
    if not isinstance(d, dict):
        raise RevenueFileBroken("최상위가 객체가 아니다")
    base = blank()
    for k, v in base.items():
        d.setdefault(k, v)
    # map_raw 가 정본. 예전 파일은 map 을 통째로 들고 있다.
    raw = d.get("map_raw")
    if not isinstance(raw, dict):
        raw = d.get("map") or {}
    d["map"] = _merge_map(raw)
    return d


_SAVE_LOCK = _threading.Lock()


def save(path, store: dict) -> None:
    """같은 이름의 임시 파일을 여럿이 동시에 쓰면 서로를 덮어쓴다."""
    import os
    out = dict(store)
    m = out.get("map") or {}
    # 사람이 고친 것만 남긴다. 기본 매핑은 코드가 들고 있으면 된다.
    raw = {k: v for k, v in m.items() if DEFAULT_MAP.get(k) != v}
    for k in DEFAULT_MAP:
        if k not in m:
            raw[k] = ""                      # 일부러 끊은 것
    out["map_raw"] = raw
    out["updated_at"] = _dt.datetime.now().isoformat(timespec="seconds")
    tmp = "%s.%d.%d.tmp" % (path, os.getpid(), _threading.get_ident())
    with _SAVE_LOCK:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(out, f, ensure_ascii=False, indent=1)
        os.replace(tmp, path)
    store["map_raw"] = raw
    store["updated_at"] = out["updated_at"]


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


def _year_for(week: int, mm: int, dd: int, hint: int = None):
    """W37 시트의 '09 / 07' 이 몇 년인지. 못 세면 None.

    파일의 해를 그대로 쓴다. 주차로 되짚으면 안 된다 — W35 시트에 08/31
    이 들어 있는데 그 날의 ISO 주차는 36 이라, 35 에 맞는 해(2025)로
    밀려난다.

    연말연시만 예외다. 2026년 파일의 W01 시트는 2025-12-29 부터라
    거기 적힌 12/29 는 '지난 해' 다. 반대로 W53 시트는 2027-01-03 까지
    가므로 01/02 는 '다음 해' 다.
    """
    y = hint or _dt.date.today().year
    if mm == 12 and week <= 2:
        y -= 1
    elif mm == 1 and week >= 52:
        y += 1
    try:
        _dt.date(y, mm, dd)
    except ValueError:
        return None          # 2월 30일 같은 칸. 세지 않는다.
    return y


def parse_daily(raw: bytes, year_hint: int = None) -> dict:
    """일일보고에서 날짜별 금액을 꺼낸다.

    시트 이름이 W## 인 것만 본다. 각 시트 머리에 '09 / 07' 같은 날짜가 있고
    그 아래 Plan / Q'ty / Amount 세 칸이 붙는다.
    """
    wb = _open(raw)
    days, rows, sheets, skipped = {}, [], [], []
    covered = set()   # 날짜 칸이 있던 날 (값이 비어 있어도 파일이 맡은 날이다)
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
            # 날짜 머리글을 못 찾았다. 조용히 지나가면 그 주가 통째로
            # 빠지는데 화면에는 아무 말도 안 나온다.
            skipped.append(ws.title)
            continue
        sheets.append(ws.title)
        # 날짜 한 칸이 늘 Plan · Q'ty · Amount 세 칸인 건 아니다. W9 처럼
        # 'Plan ($) update' 가 끼어드는 주가 있어서, 아랫줄 이름으로 찾는다.
        sub = grid[hi + 1] if len(grid) > hi + 1 else ()
        # 'W37 Total' 묶음이 마지막 날짜 칸에 딸려 들어가면, 그 날 하루가
        # 그 주 전체 합계로 잡힌다. 머리글이 날짜 줄 위/아래에 있을 수도
        # 있어서 세 줄을 다 본다.
        last = cols[-1][0] if cols else 0
        stop = max(len(sub), len(grid[hi]))
        for row in (grid[hi - 1] if hi > 0 else (), grid[hi],
                    sub if sub else ()):
            for j, v in enumerate(row):
                if v and "total" in str(v).lower() and j > last:
                    stop = min(stop, j)
        picks = []
        for n, (j, mm, dd) in enumerate(cols):
            # 머리글을 못 찾아도 남의 칸까지 넘어가지 않게 네 칸으로 막는다
            end = min(cols[n + 1][0] if n + 1 < len(cols) else stop, j + 4)
            pj = qj = aj = None
            for k in range(j, min(end, len(sub))):
                lab = norm(sub[k]).lower().replace("'", "")
                if aj is None and lab.startswith("amount"):
                    aj = k
                elif qj is None and lab.startswith("qty"):
                    qj = k
                elif pj is None and lab.startswith("plan"):
                    pj = k
            picks.append((mm, dd,
                          j if pj is None else pj,
                          j + 1 if qj is None else qj,
                          j + 2 if aj is None else aj))
            _y = _year_for(week, mm, dd, year_hint)
            if _y is not None:
                covered.add("%04d-%02d-%02d" % (_y, mm, dd))
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
                if y is None:
                    continue
                key = "%04d-%02d-%02d" % (y, mm, dd)
                cell = days.setdefault(key, {}).setdefault(
                    lab, {"plan": 0.0, "qty": 0.0, "amount": 0.0})
                cell["plan"] += plan
                cell["qty"] += qty
                cell["amount"] += amt
    return {"days": days, "rows": rows, "sheets": sheets,
            "skipped": skipped, "covered": sorted(covered)}


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
    # 해가 안 적혀 있으면 오늘에서 가장 가까운 해로 본다. 12월에 올리는
    # 'Estimate Revenue in Jan' 은 올해 1월이 아니라 내년 1월이다.
    today = _dt.date.today()
    best, gap = today.year, 99
    for y in (today.year - 1, today.year, today.year + 1):
        d = abs((y - today.year) * 12 + mm - today.month)
        if d < gap:
            best, gap = y, d
    return "%04d-%02d" % (best, mm)


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
        if isinstance(b, (int, float)):
            v = float(b)
        else:
            # '2,400,000' 처럼 글자로 적힌 칸이 있다. 버리면 그 품목이
            # 통째로 사라지고 '모르는 항목' 에도 안 뜬다.
            t = norm(b)
            if not t or not re.fullmatch(r"-?[\d,]+(\.\d+)?", t):
                continue
            v = _num(t)
        # 같은 이름이 두 줄이면 더한다 (덮어쓰면 한 줄이 사라진다)
        if a in items:
            items[a] += v
        else:
            items[a] = v
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
    """올린 파일이 맡은 기간을 통째로 갈아 끼운다.

    날짜마다 덮어쓰기만 하면, 잘못 적었던 날을 지우고 다시 올려도 옛 값이
    그대로 남는다 (빈 칸은 파일에 아예 안 나온다). 그래서 파일이 덮는
    기간 안에서 이번에 안 나온 날짜는 지운다.
    """
    days = store.setdefault("days", {})
    before = _sum_all(days)
    got = parsed.get("days") or {}
    # 파일이 맡은 날 = 날짜 칸이 있던 날. 값이 다 비어 있어도 그 날은
    # 파일이 '0 이다' 라고 말한 것이다.
    covered = set(parsed.get("covered") or got)
    dropped = []
    for day in list(days):
        if day in covered and day not in got:
            days.pop(day)
            dropped.append(day)
    for day, rowmap in got.items():
        days[day] = rowmap
    store.setdefault("sources", {})["daily"] = {
        "file": filename,
        "at": _dt.datetime.now().isoformat(timespec="seconds"),
        "sheets": parsed.get("sheets") or [],
        "skipped": parsed.get("skipped") or [],
        "days": len(got),
    }
    return {"before": before, "after": _sum_all(days),
            "days": sorted(got), "dropped": sorted(dropped)}


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

    # 계획도 실적도 0 인 줄도 자리를 지킨다. 보고서에 있는 줄이
    # 그 달만 조용하다고 사라지면, 빠진 건지 0 인 건지 알 수가 없다.
    names = set(ITEM_ORDER) | set(plan_item) | set(act)
    rows = []
    for it in names:
        p = round(plan_item.get(it, 0.0))
        a = round((act.get(it) or {}).get("amount", 0.0))
        rows.append({"item": it, "plan": p, "actual": a,
                     "qty": round((act.get(it) or {}).get("qty", 0.0)),
                     "rate": round(a * 100 / p) if p > 0 else None,
                     # 계획 한 줄이 여러 품목을 덮는다. 표에서 '계획 0'
                     # 으로 보이는 줄이 어디에 묶여 있는지 알려 준다.
                     "covers": PLAN_COVERS.get(it) or []})
    # 보고서에 적히는 순서대로. 계획 큰 순으로 그리면 매주 줄이 움직인다.
    _ord = {name: n for n, name in enumerate(ITEM_ORDER)}
    rows.sort(key=lambda r: (_ord.get(r["item"], 900), -r["plan"], r["item"]))

    for r in rows:
        r["group"] = group_of(r["item"])
    tp = sum(r["plan"] for r in rows)
    ta = sum(r["actual"] for r in rows)

    # 보고서 묶음 — 매출합계(반도체·데이터센터·우주항공) / 내부거래 / 총합
    def _box(key, label):
        got = [r for r in rows if r["group"] == key]
        p_ = sum(r["plan"] for r in got)
        a_ = sum(r["actual"] for r in got)
        return {"key": key, "label": label, "plan": p_, "actual": a_,
                "rate": round(a_ * 100 / p_) if p_ > 0 else None,
                "items": got}

    boxes = [_box(k, lb) for k, lb in GROUPS]
    internal = _box(INTERNAL[0], INTERNAL[1])
    sub_p = sum(b["plan"] for b in boxes)
    sub_a = sum(b["actual"] for b in boxes)
    # 누적은 '보고 있는 달까지' 다. 8월을 보는데 9월 실적이 누적에
    # 들어가면 1~8월 합과 안 맞는다.
    year = month[:4]
    ytd = 0.0
    for day, rowmap in days.items():
        if not str(day).startswith(year) or str(day)[:7] > month:
            continue
        one = {}
        _fold(store, rowmap, one)
        ytd += sum(v["amount"] for v in one.values())
    return {
        "month": month, "items": rows,
        "groups": boxes,
        "internal": internal,
        "subtotal": {"label": "소계 (Sub-total)", "plan": sub_p, "actual": sub_a,
                     "rate": round(sub_a * 100 / sub_p) if sub_p > 0 else None},
        "grand": {"label": "총합 (내부거래 포함)", "plan": tp, "actual": ta,
                  "rate": round(ta * 100 / tp) if tp > 0 else None},
        "plan": tp, "actual": ta,
        "rate": round(ta * 100 / tp) if tp > 0 else None,
        "left": max(0, tp - ta),
        "ytd": round(ytd),
        "as_of": last_day,
        "has_data": bool(rows),
        "sources": store.get("sources") or {},
    }
