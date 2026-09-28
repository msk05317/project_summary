"""'월별 매입 현황 분석' 엑셀을 읽는다.

표 모양은 행이 구분, 열이 월이다.

                4월      5월      6월   ...  합계
  매출액      1,742,300 ...
  원소재  매입액  ...
          지급액  ...
          잔액    ...
  소모품  매입액  ...
  ...
  합계    매입액  ...        ← 우리가 더해서 만든다. 읽지 않는다.
  선급금          ...
  실지급액        ...
  실비투자        ...

항목 이름(원소재/소모품/기타/외주)은 병합 셀이라 위 칸에만 적혀 있다.
그래서 왼쪽 라벨은 '마지막으로 본 값'을 끌고 내려간다.

빈 칸은 덮어쓰지 않는다. 엑셀에 안 적힌 달을 지우면, 손으로 넣은 값이
한 번 올릴 때마다 날아간다.
"""
from __future__ import annotations

import datetime as _dt
import re

import purchases as _pur

# 항목 이름 → 키. 못 알아보면 이름을 그대로 쓰고 키만 만들어 준다.
ITEM_KEYS = (
    ("raw", ("원소재", "원자재", "raw")),
    ("supply", ("소모품", "소모", "supply")),
    ("etc", ("기타", "약품", "포장")),
    ("outsourcing", ("외주", "외주가공", "outsourc")),
)

_MONTH_RE = re.compile(r"^\s*(\d{1,2})\s*월")
_YM_RE = re.compile(r"^\s*(20\d\d)[-./]\s*(\d{1,2})")
_YEAR_RE = re.compile(r"(20\d\d)\s*년?")
_SKIP_LABEL = ("합계", "소계", "총계", "누계", "계")


def _s(v) -> str:
    if v is None:
        return ""
    if isinstance(v, _dt.datetime):
        return v.strftime("%Y-%m")
    return str(v).strip()


def _item_key(label: str, used: set) -> str:
    t = label.replace(" ", "").lower()
    for key, words in ITEM_KEYS:
        for w in words:
            if w in t:
                return key
    base = re.sub(r"[^a-z0-9]+", "", t) or "item"
    k = base[:16]
    i = 2
    while k in used:
        k = "%s%d" % (base[:14], i)
        i += 1
    return k


def _grid(ws, max_row=400, max_col=40):
    out = []
    for r in ws.iter_rows(min_row=1, max_row=min(ws.max_row or 1, max_row),
                          max_col=min(ws.max_column or 1, max_col),
                          values_only=True):
        out.append(list(r))
    return out


def _find_year(grid, sheet_name: str, default_year: int) -> int:
    m = _YEAR_RE.search(sheet_name or "")
    if m:
        return int(m.group(1))
    for row in grid[:12]:
        for c in row:
            m = _YEAR_RE.search(_s(c))
            if m:
                return int(m.group(1))
    return default_year


def _header(grid, year: int):
    """월이 2개 이상 있는 줄을 머리글로 본다. → (행번호, {열: 'YYYY-MM'})"""
    best = None
    for ri, row in enumerate(grid[:40]):
        cols = {}
        for ci, cell in enumerate(row):
            t = _s(cell)
            if not t:
                continue
            if any(w == t.replace(" ", "") for w in _SKIP_LABEL):
                continue
            m = _YM_RE.match(t)
            if m:
                cols[ci] = "%04d-%02d" % (int(m.group(1)), int(m.group(2)))
                continue
            m = _MONTH_RE.match(t)
            if m:
                mm = int(m.group(1))
                if 1 <= mm <= 12:
                    # 연말→연초로 넘어가면 해가 바뀐다
                    cols[ci] = "%04d-%02d" % (year, mm)
        if len(cols) >= 2 and (best is None or len(cols) > len(best[1])):
            best = (ri, cols)
    return best


def _roll_year(cols: dict) -> dict:
    """4월,5월,...,12월,1월 이면 1월부터 다음 해다."""
    out, prev, bump = {}, 0, 0
    for ci in sorted(cols):
        y, m = cols[ci].split("-")
        mm = int(m)
        if prev and mm < prev:
            bump += 1
        prev = mm
        out[ci] = "%04d-%02d" % (int(y) + bump, mm)
    return out


TOP_WORDS = ("매출", "선급", "실지급", "실비")


def _is_top(label: str) -> bool:
    """항목이 아니라 표 맨 왼쪽 구분인가 — 매출액 · 선급금 · 실지급액 · 실비투자."""
    t = label.replace(" ", "")
    return any(w in t for w in TOP_WORDS)


def _labels(row, upto: int):
    """머리글 왼쪽 라벨 칸들 — 비어 있지 않은 것만 순서대로."""
    return [_s(c) for c in row[:upto] if _s(c)]


def parse_sheet(ws, default_year: int):
    grid = _grid(ws)
    if not grid:
        return None
    year = _find_year(grid, ws.title, default_year)
    head = _header(grid, year)
    if not head:
        return None
    hrow, cols = head
    cols = _roll_year(cols)
    first_col = min(cols)

    months = {m: {"revenue": None, "items": {}, "prepaid": None,
                  "actual_paid": None, "invest": None} for m in cols.values()}
    order, used = [], set()
    cat = ""
    warnings = []

    for row in grid[hrow + 1:]:
        labs = _labels(row, first_col)
        if not labs:
            continue
        if len(labs) >= 2:
            cat, sub = labs[0], labs[1]
        else:
            one = labs[0]
            # 한 칸만 있으면 그게 구분일 수도(매출액·선급금), 소분류일 수도
            # (항목 이름이 병합돼서 '지급액' 만 남은 줄) 있다. '실지급액' 처럼
            # 둘 다처럼 보이는 이름이 있어서 구분 쪽을 먼저 본다.
            if _is_top(one):
                cat, sub = one, ""
            elif any(w in one.replace(" ", "") for w in ("매입", "지급", "잔액", "미지급")):
                sub = one                 # 위에서 끌고 온 cat 을 쓴다
            else:
                cat, sub = one, ""

        c = cat.replace(" ", "")
        s = sub.replace(" ", "")
        if any(c == w for w in _SKIP_LABEL):
            continue                       # 합계 줄은 우리가 만든다

        vals = {m: _pur._num(row[ci]) if ci < len(row) else None
                for ci, m in cols.items()}
        if not any(v is not None for v in vals.values()):
            continue

        field = None
        if "매출" in c and not s:
            field = ("revenue", None)
        elif "선급" in c:
            field = ("prepaid", None)
        elif "실지급" in c:
            field = ("actual_paid", None)
        elif "실비" in c:
            field = ("invest", None)
        elif "매입" in s:
            field = ("item", "buy")
        elif "지급" in s:
            field = ("item", "paid")
        elif "잔액" in s or "미지급" in s:
            field = ("item", "balance")

        if field is None:
            if c and c not in [w for w in _SKIP_LABEL]:
                warnings.append("못 알아본 줄: %s %s" % (cat, sub))
            continue

        if field[0] != "item":
            for m, v in vals.items():
                if v is not None:
                    months[m][field[0]] = v
            continue

        key = _item_key(cat, used)
        if key not in used:
            used.add(key)
            order.append((key, cat.strip()))
        for m, v in vals.items():
            if v is None:
                continue
            months[m]["items"].setdefault(key, {})[field[1]] = v

    # 항목이 하나도 없으면 이 시트가 아니다
    if not order:
        return None

    out = {}
    for m, mv in months.items():
        items = []
        for key, label in order:
            got = mv["items"].get(key) or {}
            items.append({"key": key, "label": label,
                          "buy": got.get("buy"), "paid": got.get("paid"),
                          "balance": got.get("balance")})
        if not any(i["buy"] is not None or i["paid"] is not None
                   or i["balance"] is not None for i in items) \
                and mv["revenue"] is None:
            continue                       # 아무것도 안 적힌 달은 건너뛴다
        out[m] = {"revenue": mv["revenue"], "items": items,
                  "prepaid": mv["prepaid"], "actual_paid": mv["actual_paid"],
                  "invest": mv["invest"], "note": ""}
    if not out:
        return None
    return {"sheet": ws.title, "months": out, "warnings": warnings,
            "items": [{"key": k, "label": l} for k, l in order]}


def parse_workbook(path_or_file, default_year=None):
    import openpyxl
    wb = openpyxl.load_workbook(path_or_file, data_only=True, read_only=True)
    year = default_year or _dt.date.today().year
    best = None
    for ws in wb.worksheets:
        try:
            got = parse_sheet(ws, year)
        except Exception as e:                       # 한 시트가 이상해도 계속
            got = None
            best = best or None
            _ = e
        if got and (best is None or len(got["months"]) > len(best["months"])):
            best = got
    if best is None:
        raise ValueError("월별 매입 표를 찾지 못했습니다. "
                         "월(4월·5월…)이 가로로, 항목이 세로로 있는 시트여야 합니다.")
    return best


# ---------------------------------------------------------------- 합치기


def merge_keep(old_months: dict, new_months: dict) -> dict:
    """엑셀에 없는 달·빈 칸은 그대로 둔다."""
    out = {m: dict(v) for m, v in (old_months or {}).items()}
    for m, nv in (new_months or {}).items():
        ov = out.get(m) or {}
        cur = _pur.normalize_month(ov) if ov else None
        merged = {
            "revenue": nv.get("revenue") if nv.get("revenue") is not None
            else (cur or {}).get("revenue"),
            "prepaid": nv.get("prepaid") if nv.get("prepaid") is not None
            else (cur or {}).get("prepaid"),
            "actual_paid": nv.get("actual_paid") if nv.get("actual_paid") is not None
            else (cur or {}).get("actual_paid"),
            "invest": nv.get("invest") if nv.get("invest") is not None
            else (cur or {}).get("invest"),
            "note": (cur or {}).get("note", ""),
        }
        old_items = {i.get("key"): i for i in ((cur or {}).get("items") or [])}
        items = []
        for it in nv.get("items") or []:
            o = old_items.pop(it.get("key"), {}) or {}
            items.append({
                "key": it.get("key"), "label": it.get("label") or o.get("label"),
                "buy": it.get("buy") if it.get("buy") is not None else o.get("buy"),
                "paid": it.get("paid") if it.get("paid") is not None else o.get("paid"),
                "balance": it.get("balance") if it.get("balance") is not None
                else o.get("balance"),
            })
        for k, o in old_items.items():          # 엑셀에 없던 항목도 남긴다
            items.append(o)
        merged["items"] = items
        out[m] = merged
    return out


def diff(old_months: dict, new_months: dict):
    """미리보기용 — 달마다 뭐가 바뀌는지 한 줄씩."""
    rows = []
    for m in sorted(new_months or {}):
        nv = _pur.normalize_month(new_months[m])
        nb = sum(_pur._f(i.get("buy")) for i in nv["items"])
        np_ = sum(_pur._f(i.get("paid")) for i in nv["items"])
        ov = (old_months or {}).get(m)
        if ov is None:
            rows.append({"month": m, "kind": "new", "buy": nb, "paid": np_,
                         "was_buy": None, "was_paid": None})
            continue
        o = _pur.normalize_month(ov)
        ob = sum(_pur._f(i.get("buy")) for i in o["items"])
        op = sum(_pur._f(i.get("paid")) for i in o["items"])
        rows.append({"month": m, "kind": "same" if (ob == nb and op == np_) else "update",
                     "buy": nb, "paid": np_, "was_buy": ob, "was_paid": op})
    return rows
