"""사업부 월별 매입·지급 현황 (v2 — 해외/국내 + 재고 + 비고).

엑셀 '월별 매입 현황 분석'을 그대로 담는다. 한 칸이 이제 숫자 하나가
아니라 셋이다.

    {"total": 8776516, "overseas": 3510607, "domestic": 5265910}

안 적은 칸은 None 으로 남긴다. 0 과 '안 적음'은 다르다 — 해외를 아직
안 나눈 달은 합계만 있고, 앱은 그 달의 해외 탭에서 '미입력' 이라고
말해야 한다. 0 으로 채우면 없는 게 아니라 0원인 것처럼 읽힌다.

잔액은 계산하지 않고 '적힌 값'을 쓴다. 표의 잔액이 매입-지급과 맞지
않는 달이 있어서다. 비워두면 그때만 매입-지급으로 채운다.

비고는 줄바꿈을 그대로 지킨다. '/' 로 이어 붙이면 몇 건인지 세려고
눈으로 훑어야 한다.
"""
from __future__ import annotations

import datetime as _dt
import json
import re
from pathlib import Path

CURRENCIES = ("USD", "KRW")
REGIONS = ("total", "overseas", "domestic")
REGION_LABEL = {"total": "합계", "overseas": "해외", "domestic": "국내"}
METRICS = ("buy", "paid", "balance")

MAX_MONTHS = 60
MAX_ITEMS = 12
MAX_LABEL = 40
MAX_NOTE = 600

DEFAULT_ITEMS = (
    ("raw", "원소재"),
    ("supply", "소모품"),
    ("etc", "기타 (약품·포장재 등)"),
    ("outsourcing", "외주"),
)
# 재고는 항목이 고정이다 (엑셀의 재고 블록 그대로)
STOCK_ROWS = (
    ("available", "가용 원재고"),
    ("dead", "불용 원자재"),
    ("wip", "재공 재고"),
    ("finished", "완제품 재고"),
)

_MONTH_RE = re.compile(r"^20\d\d-(0[1-9]|1[0-2])$")
_KEY_RE = re.compile(r"^[a-z0-9_]{1,24}$")


def _s(v) -> str:
    return "" if v is None else str(v).strip()


def _note(v) -> str:
    """비고 — 줄바꿈은 지키고 줄 끝 공백만 턴다."""
    t = "" if v is None else str(v)
    t = t.replace("\r\n", "\n").replace("\r", "\n")
    lines = [ln.rstrip() for ln in t.split("\n")]
    while lines and not lines[0]:
        lines.pop(0)
    while lines and not lines[-1]:
        lines.pop()
    return "\n".join(lines)[:MAX_NOTE]


def _num(v):
    """빈 칸은 None 으로 남긴다 — 0 과 '안 적음' 은 다르다."""
    if v is None or isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    t = _s(v).replace(",", "").replace("$", "").replace("₩", "")
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


def _f(v) -> float:
    n = _num(v)
    return 0.0 if n is None else n


def _month(v) -> str:
    t = _s(v)[:7]
    return t if _MONTH_RE.match(t) else ""


def _key(v, fallback: str) -> str:
    t = _s(v).lower()
    return t if _KEY_RE.match(t) else fallback


# ── 한 칸 = 합계/해외/국내 ─────────────────────────────────────


def cell(raw) -> dict:
    """숫자 하나로 적힌 옛 데이터도 받는다 (그건 합계로 본다)."""
    if isinstance(raw, dict):
        return {r: _num(raw.get(r)) for r in REGIONS}
    return {"total": _num(raw), "overseas": None, "domestic": None}


def cell_get(c: dict, region: str):
    return (c or {}).get(region if region in REGIONS else "total")


def cell_has(c: dict) -> bool:
    return any((c or {}).get(r) is not None for r in REGIONS)


def normalize_item(raw, idx: int) -> dict:
    raw = raw if isinstance(raw, dict) else {}
    dk, dl = (DEFAULT_ITEMS[idx] if idx < len(DEFAULT_ITEMS)
              else ("item%d" % (idx + 1), "항목%d" % (idx + 1)))
    out = {
        "key": _key(raw.get("key"), dk),
        "label": (_s(raw.get("label")) or dl)[:MAX_LABEL],
        "note": _note(raw.get("note")),
    }
    for m in METRICS:
        out[m] = cell(raw.get(m))
    return out


def normalize_stock(raw) -> list:
    """저장은 리스트로 하고 입력은 dict 로도 받는다.

    한 번 저장한 뒤 다시 읽을 때 리스트를 못 알아보면 재고가 통째로
    비워진다 — 실제로 그렇게 한 번 날렸다.
    """
    rows = {}
    if isinstance(raw, dict):
        rows = raw
    elif isinstance(raw, list):
        for r in raw:
            if isinstance(r, dict) and _s(r.get("key")):
                rows[_s(r.get("key"))] = r
    out = []
    for k, label in STOCK_ROWS:
        r = rows.get(k)
        r = r if isinstance(r, dict) else {}
        out.append({"key": k, "label": label,
                    "value": cell(r.get("value")),
                    "note": _note(r.get("note"))})
    return out


def normalize_month(raw) -> dict:
    raw = raw if isinstance(raw, dict) else {}
    items_raw = raw.get("items")
    if not isinstance(items_raw, list) or not items_raw:
        items_raw = [{"key": k, "label": l} for k, l in DEFAULT_ITEMS]
    items = [normalize_item(it, i) for i, it in enumerate(items_raw[:MAX_ITEMS])]
    seen, clean = set(), []
    for it in items:
        k = it["key"]
        while k in seen:
            k += "_"
        it["key"] = k[:24]
        seen.add(it["key"])
        clean.append(it)
    return {
        "revenue": cell(raw.get("revenue")),
        "items": clean,
        "prepaid": cell(raw.get("prepaid")),
        "actual_paid": cell(raw.get("actual_paid")),
        "invest": cell(raw.get("invest")),
        "stock": normalize_stock(raw.get("stock")),
        "receivable": cell(raw.get("receivable")),     # 외상 매출 (미수금)
        "total_buy": cell(raw.get("total_buy")),       # 총 매입액 (표의 값)
        "note": _note(raw.get("note")),
    }


def normalize(data) -> dict:
    data = data if isinstance(data, dict) else {}
    divs_raw = data.get("divisions")
    divs = {}
    if isinstance(divs_raw, dict):
        for div, body in divs_raw.items():
            div = _s(div)
            if not div:
                continue
            body = body if isinstance(body, dict) else {}
            cur = _s(body.get("currency")).upper()
            months_raw = body.get("months") if isinstance(body.get("months"), dict) else {}
            months = {}
            for m, mv in months_raw.items():
                mk = _month(m)
                if mk:
                    months[mk] = normalize_month(mv)
            if len(months) > MAX_MONTHS:
                for mk in sorted(months)[:-MAX_MONTHS]:
                    months.pop(mk, None)
            divs[div] = {"currency": cur if cur in CURRENCIES else "USD",
                         "months": months}
    return {"version": 2, "updated_at": _s(data.get("updated_at")), "divisions": divs}


def load(path: Path) -> dict:
    try:
        return normalize(json.loads(Path(path).read_text(encoding="utf-8")))
    except Exception:
        return normalize({})


def save(path: Path, data: dict) -> dict:
    out = normalize(data)
    out["updated_at"] = _dt.datetime.now().isoformat(timespec="seconds")
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    return out


# ── 보기 ─────────────────────────────────────────────────────


def _resolve(mv: dict, region: str) -> dict:
    """한 달치를 앱이 그릴 수 있는 형태로 푼다. 한 지역만 본다."""
    items, buy, paid, bal = [], 0.0, 0.0, 0.0
    for it in mv.get("items") or []:
        b = _f(cell_get(it.get("buy"), region))
        p = _f(cell_get(it.get("paid"), region))
        raw_bal = cell_get(it.get("balance"), region)
        r = b - p if raw_bal is None else float(raw_bal)
        if b == 0 and p == 0 and r == 0:
            continue                      # 세 칸이 다 0인 항목은 화면에서 뺀다
        items.append({
            "key": it.get("key", ""), "label": it.get("label", ""),
            "buy": b, "paid": p, "balance": r,
            "balance_auto": raw_bal is None,
            "pay_rate": round(p / b * 100, 1) if b > 0 else 0.0,
            "note": it.get("note", ""),
            "by_region": {rg: {m: cell_get(it.get(m), rg) for m in METRICS}
                          for rg in REGIONS},
        })
        buy += b
        paid += p
        bal += r

    rev = _f(cell_get(mv.get("revenue"), region))
    prepaid = _f(cell_get(mv.get("prepaid"), region))
    actual = _f(cell_get(mv.get("actual_paid"), region))
    invest = cell_get(mv.get("invest"), region)

    stock, stock_sum = [], 0.0
    for r in mv.get("stock") or []:
        v = cell_get(r.get("value"), region)
        stock.append({"key": r.get("key"), "label": r.get("label"),
                      "value": None if v is None else float(v),
                      "note": r.get("note", "")})
        if r.get("key") in ("wip", "finished") and v is not None:
            stock_sum += float(v)

    total_buy = cell_get(mv.get("total_buy"), region)
    receivable = cell_get(mv.get("receivable"), region)
    ratio = (round(float(total_buy) / rev * 100, 1)
             if (total_buy is not None and rev > 0) else None)

    return {
        "region": region, "region_label": REGION_LABEL.get(region, region),
        "revenue": rev,
        "buy": buy, "paid": paid, "balance": bal,
        "pay_rate": round(paid / buy * 100, 1) if buy > 0 else 0.0,
        "items": items,
        "payment": {"prepaid": prepaid, "actual_paid": actual,
                    "invest": None if invest is None else float(invest),
                    "total": prepaid + actual + (0.0 if invest is None else float(invest))},
        "stock": stock,
        "stock_total": stock_sum,
        "receivable": None if receivable is None else float(receivable),
        "total_buy": None if total_buy is None else float(total_buy),
        "buy_over_revenue": ratio,
        "note": mv.get("note", ""),
        "has_data": any(cell_has(mv.get(k)) for k in
                        ("revenue", "prepaid", "actual_paid", "invest",
                         "receivable", "total_buy"))
        or bool(items) or any(x["value"] is not None for x in stock),
    }


def month_label(m: str) -> str:
    try:
        return "%d월" % int(m[5:7])
    except Exception:
        return m


def _sum_months(months: list) -> dict:
    """누적. 항목은 키로 합치고, 재고는 마지막 달 값을 쓴다 —
    재고는 시점 값이라 더하면 없는 숫자가 된다."""
    tot = {"revenue": 0.0, "buy": 0.0, "paid": 0.0, "balance": 0.0,
           "receivable": None, "total_buy": None}
    acc, order, labels, notes = {}, [], {}, {}
    pay = {"prepaid": 0.0, "actual_paid": 0.0, "invest": None, "total": 0.0}
    for m in months:
        for k in ("revenue", "buy", "paid", "balance"):
            tot[k] += m[k]
        for nm in ("receivable", "total_buy"):
            if m.get(nm) is not None:
                tot[nm] = (tot[nm] or 0.0) + m[nm]
        for it in m["items"]:
            k = it["key"]
            if k not in acc:
                acc[k] = {"key": k, "label": it["label"], "buy": 0.0, "paid": 0.0,
                          "balance": 0.0, "balance_auto": True, "pay_rate": 0.0,
                          "note": "", "by_region": {}}
                order.append(k)
            labels[k] = it["label"]
            if it.get("note"):
                notes[k] = it["note"]
            acc[k]["buy"] += it["buy"]
            acc[k]["paid"] += it["paid"]
            acc[k]["balance"] += it["balance"]
        p = m["payment"]
        pay["prepaid"] += p["prepaid"]
        pay["actual_paid"] += p["actual_paid"]
        if p["invest"] is not None:
            pay["invest"] = (pay["invest"] or 0.0) + p["invest"]
    for k in order:
        a = acc[k]
        a["label"] = labels[k]
        a["note"] = notes.get(k, "")
        a["pay_rate"] = round(a["paid"] / a["buy"] * 100, 1) if a["buy"] > 0 else 0.0
    pay["total"] = pay["prepaid"] + pay["actual_paid"] + (pay["invest"] or 0.0)
    tot["pay_rate"] = round(tot["paid"] / tot["buy"] * 100, 1) if tot["buy"] > 0 else 0.0
    tot["items"] = [acc[k] for k in order]
    tot["payment"] = pay
    last = months[-1] if months else None
    tot["stock"] = last["stock"] if last else []
    tot["stock_total"] = last["stock_total"] if last else 0.0
    tot["buy_over_revenue"] = (round(tot["total_buy"] / tot["revenue"] * 100, 1)
                               if (tot.get("total_buy") and tot["revenue"] > 0) else None)
    tot["note"] = ""
    tot["has_data"] = True
    return tot


def region_filled(body: dict) -> dict:
    """어느 지역이 한 번이라도 적혔는지. 앱이 탭을 흐리게 할 때 쓴다."""
    out = {r: False for r in REGIONS}
    for mv in (body.get("months") or {}).values():
        for c in ([mv.get("revenue"), mv.get("prepaid"), mv.get("actual_paid"),
                   mv.get("invest"), mv.get("receivable"), mv.get("total_buy")]
                  + [it.get(m) for it in (mv.get("items") or []) for m in METRICS]
                  + [r.get("value") for r in (mv.get("stock") or [])]):
            for r in REGIONS:
                if (c or {}).get(r) is not None:
                    out[r] = True
    return out


def for_app(data: dict, div: str, region: str = "total") -> dict:
    region = region if region in REGIONS else "total"
    body = (data.get("divisions") or {}).get(div) or {}
    months_raw = body.get("months") or {}
    keys = sorted(months_raw)[-12:]
    months = []
    for m in keys:
        v = _resolve(months_raw[m], region)
        v["month"] = m
        v["label"] = month_label(m)
        months.append(v)
    total = _sum_months(months)
    total["month"] = "total"
    total["label"] = "누적"
    total["region"] = region
    total["region_label"] = REGION_LABEL.get(region, region)
    total["range"] = ("%s~%s" % (month_label(keys[0]), month_label(keys[-1]))
                      if keys else "")
    return {
        "division": div,
        "currency": body.get("currency") or "USD",
        "region": region,
        "regions": [{"key": r, "label": REGION_LABEL[r]} for r in REGIONS],
        "regions_filled": region_filled(body),
        "has_data": bool(keys),
        "latest": keys[-1] if keys else "",
        "months": months,
        "total": total,
    }


def for_admin(data: dict, div: str) -> dict:
    body = (data.get("divisions") or {}).get(div) or {}
    months_raw = body.get("months") or {}
    return {
        "division": div,
        "currency": body.get("currency") or "USD",
        "months": {m: months_raw[m] for m in sorted(months_raw)},
        "default_items": [{"key": k, "label": l} for k, l in DEFAULT_ITEMS],
        "stock_rows": [{"key": k, "label": l} for k, l in STOCK_ROWS],
        "regions": [{"key": r, "label": REGION_LABEL[r]} for r in REGIONS],
    }


def put_division(data: dict, div: str, payload: dict) -> dict:
    """한 사업부 통째로 갈아끼운다 — 화면이 전체를 들고 있다."""
    out = normalize(data)
    payload = payload if isinstance(payload, dict) else {}
    months = payload.get("months") if isinstance(payload.get("months"), dict) else {}
    cur = _s(payload.get("currency")).upper()
    clean = {}
    for m, mv in months.items():
        mk = _month(m)
        if mk:
            clean[mk] = normalize_month(mv)
    out["divisions"][div] = {"currency": cur if cur in CURRENCIES else "USD",
                             "months": clean}
    return out
