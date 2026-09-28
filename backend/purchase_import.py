"""'월별 매입 현황 분석' 엑셀 읽기.

시트 모양이 달마다 조금씩 달라서 좌표를 박지 않는다. 대신
  1) 월이 적힌 머리줄을 찾아 '어느 열이 몇 월인지' 를 만들고
  2) 왼쪽 라벨을 보며 줄을 해석한다.
'합계' 열과 '합계' 줄은 읽지 않는다 — 우리가 더해서 확인하는 쪽이 낫다.

못 알아본 줄은 버리지 않고 warnings 로 올려 보낸다. 조용히 빠진 줄이
제일 위험하다.
"""
from __future__ import annotations

import datetime as _dt
import io
import re

from openpyxl import load_workbook

ITEM_KEYS = [
    ("raw", ("원소재", "원자재")),
    ("supply", ("소모품", "소모자재")),
    ("etc", ("기타", "약품", "포장재")),
    ("outsourcing", ("외주", "외주가공")),
]
ITEM_LABEL = {"raw": "원소재", "supply": "소모품",
              "etc": "기타 (약품·포장재 등)", "outsourcing": "외주"}
METRICS = {
    "buy": ("매입액", "매입", "구매액", "구매"),
    "paid": ("지급액", "지급", "결제액"),
    "balance": ("잔액", "미지급", "잔여"),
}
PAYMENT = {
    "prepaid": ("선급금", "선급"),
    "actual_paid": ("실지급액", "실지급"),
    "invest": ("실비투자", "실비"),
}
REVENUE = ("매출액", "매출")
SKIP_IN = ("합계", "총계", "소계")      # 어디에 끼어 있어도 건너뛴다
SKIP_EQ = ("계", "total")                 # 딱 그 글자일 때만

_MONTH_TXT = re.compile(r"(?:^|\D)(1[0-2]|0?[1-9])\s*월")


def _txt(v) -> str:
    if v is None:
        return ""
    if isinstance(v, (_dt.datetime, _dt.date)):
        return "%d월" % v.month
    return str(v).replace(" ", " ").strip()


def _norm(s) -> str:
    return re.sub(r"[\s()（）\[\]·.,/]+", "", _txt(s)).lower()


def _num(v):
    if v is None or isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    t = _txt(v).replace(",", "").replace("$", "").replace("₩", "")
    if not t or t in ("-", "—", "–"):
        return None
    neg = False
    if t.startswith("(") and t.endswith(")"):
        neg, t = True, t[1:-1].strip()
    elif t.startswith("-"):
        neg, t = True, t[1:].strip()
    try:
        f = float(t)
    except ValueError:
        return None
    return -f if neg else f


def _is_skip(s) -> bool:
    """'합계 매입액' 같은 줄도 건너뛴다 — 우리가 더해서 확인한다."""
    n = _norm(s)
    if not n:
        return False
    if any(_norm(w) in n for w in SKIP_IN):
        return True
    return n in {_norm(k) for k in SKIP_EQ}


def _month_of(v, year: int):
    if isinstance(v, (_dt.datetime, _dt.date)):
        return "%04d-%02d" % (v.year, v.month)
    t = _txt(v)
    if not t or _is_skip(t):
        return None
    m = re.match(r"^(20\d\d)[-./\s]+(1[0-2]|0?[1-9])$", t)
    if m:
        return "%04d-%02d" % (int(m.group(1)), int(m.group(2)))
    m = _MONTH_TXT.search(t)
    if m:
        return "%04d-%02d" % (year, int(m.group(1)))
    return None


def _item_key(label):
    n = _norm(label)
    if not n:
        return None
    for key, words in ITEM_KEYS:
        for w in words:
            if _norm(w) in n:
                return key
    return None


def _metric(label):
    n = _norm(label)
    if not n:
        return None
    for key, words in METRICS.items():
        if any(_norm(w) == n for w in words):
            return key
    for key, words in METRICS.items():
        if any(_norm(w) in n for w in words):
            return key
    return None


def _grid(ws, max_row=400, max_col=40):
    out = []
    for r in ws.iter_rows(min_row=1, max_row=min(ws.max_row or 1, max_row),
                          max_col=min(ws.max_column or 1, max_col)):
        out.append([c.value for c in r])
    return out


def _header(rows, year: int):
    """월이 2개 이상 있는 줄을 머리줄로 본다."""
    best, best_i = {}, -1
    for i, row in enumerate(rows[:40]):
        cols, seen = {}, set()
        for j, v in enumerate(row):
            m = _month_of(v, year)
            if m and m not in seen:
                cols[j] = m
                seen.add(m)
        if len(cols) >= 2 and len(cols) > len(best):
            best, best_i = cols, i
    return best_i, best


def parse_workbook(data: bytes, year=None, sheet=None) -> dict:
    year = int(year or _dt.date.today().year)
    wb = load_workbook(io.BytesIO(data), data_only=True)
    ws = wb[sheet] if (sheet and sheet in wb.sheetnames) else wb[wb.sheetnames[0]]

    rows = _grid(ws)
    hi, cols = _header(rows, year)
    if not cols:
        raise ValueError("월(4월·5월…)이 적힌 머리줄을 찾지 못했습니다.")

    acc = {m: {"revenue": None, "items": {}, "prepaid": None,
               "actual_paid": None, "invest": None} for m in cols.values()}
    warnings, read = [], []
    first_data_col = min(cols)
    label_cols = list(range(0, first_data_col)) or [0]
    cur_item = None
    skip_group = False   # '합계' 묶음 안이면 딸린 줄도 같이 건너뛴다

    for ri in range(hi + 1, len(rows)):
        row = rows[ri]
        labels = [_txt(row[j]) if j < len(row) else "" for j in label_cols]
        joined = " ".join([t for t in labels if t]).strip()
        vals = {m: (_num(row[j]) if j < len(row) else None) for j, m in cols.items()}
        has_num = any(v is not None for v in vals.values())

        head = _txt(row[label_cols[0]]) if label_cols[0] < len(row) else ""
        if head:
            skip_group = _is_skip(head)

        ik = _item_key(joined)
        if skip_group or _is_skip(joined):
            cur_item = None      # 합계 줄 밑에 딸려오는 값이 앞 항목에 붙지 않게
            continue
        if ik:
            cur_item = ik

        if not has_num:
            continue

        n = _norm(joined)
        target = None
        if not ik and any(_norm(w) in n for w in REVENUE):
            target = ("revenue", None)
        if target is None:
            for key, words in PAYMENT.items():
                if any(_norm(w) in n for w in words):
                    target = (key, None)
                    break
        if target is None:
            mk = _metric(joined)
            if mk and cur_item:
                target = ("item", (cur_item, mk))
        if target is None:
            if joined and not _is_skip(joined):
                warnings.append("알 수 없는 줄: %s" % joined[:40])
            continue

        for m, v in vals.items():
            if v is None:
                continue
            if target[0] == "item":
                ikey, mkey = target[1]
                acc[m]["items"].setdefault(ikey, {})[mkey] = v
            else:
                acc[m][target[0]] = v
        read.append(joined[:40])

    out = {}
    for m, mv in acc.items():
        items = []
        for key, _w in ITEM_KEYS:
            got = mv["items"].get(key)
            if not got:
                continue
            items.append({"key": key, "label": ITEM_LABEL[key],
                          "buy": got.get("buy"), "paid": got.get("paid"),
                          "balance": got.get("balance")})
        if not items and mv["revenue"] is None:
            continue
        out[m] = {"revenue": mv["revenue"], "items": items,
                  "prepaid": mv["prepaid"], "actual_paid": mv["actual_paid"],
                  "invest": mv["invest"], "note": ""}

    if not out:
        raise ValueError("읽을 수 있는 숫자가 없습니다. 시트를 확인해 주세요.")

    return {"sheet": ws.title, "sheets": wb.sheetnames, "year": year,
            "months": out, "read": read, "warnings": warnings}


def merge(old: dict, new: dict) -> dict:
    """엑셀에 없는 달은 그대로 둔다. 있는 달은 통째로 바꾼다."""
    out = dict(old or {})
    for m, mv in (new or {}).items():
        out[m] = mv
    return out
