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

누적(summary)은 달들을 더해서 만들지 않고 따로 담는다. 엑셀의 '합계'
열이 달 합과 안 맞는 줄이 있다 — 매출 합계가 4~8월 합보다 31만 크다.
어느 쪽이 맞는지는 표를 쓴 사람이 안다. 게다가 해외/국내는 달별로
안 나눠져 있고 누적에만 있다. 그래서 적힌 값을 적힌 대로 둔다.
누적이 없으면 예전처럼 달을 더해서 보여 준다.
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
                    "value": cell(r.get("value"))})
    return out


MAX_NOTES = 80
_NOTE_PATH = re.compile(r"^(revenue|prepaid|actual_paid|invest|receivable|total_buy"
                        r"|item:[a-z0-9_]{1,24}:(buy|paid|balance)"
                        r"|stock:(available|dead|wip|finished)"
                        r"|sum:(buy|paid|balance)|ratio|month)$")


def normalize_notes(raw, items_raw, stock_raw) -> dict:
    """비고는 줄마다 하나다 — 매출액·매입액·지급액·잔액에 각각 적는다.

    한 항목에 하나만 달 수 있던 때 잔액 줄에 몰아 적었다. 옛 데이터의
    그 비고는 그 항목의 잔액 줄로 옮긴다.
    """
    out = {}
    if isinstance(raw, dict):
        for k, v in raw.items():
            k = _s(k)
            if _NOTE_PATH.match(k):
                t = _note(v)
                if t:
                    out[k] = t
    # 옛 모양: 항목·재고에 직접 붙어 있던 비고
    if isinstance(items_raw, list):
        for it in items_raw:
            if not isinstance(it, dict):
                continue
            t = _note(it.get("note"))
            k = _key(it.get("key"), "")
            if t and k:
                out.setdefault("item:%s:balance" % k, t)
    if isinstance(stock_raw, (list, dict)):
        rows = stock_raw.values() if isinstance(stock_raw, dict) else stock_raw
        keys = list(stock_raw.keys()) if isinstance(stock_raw, dict) else None
        for i, r in enumerate(rows):
            if not isinstance(r, dict):
                continue
            k = _s(r.get("key")) or (keys[i] if keys else "")
            t = _note(r.get("note"))
            if t and k:
                out.setdefault("stock:%s" % k, t)
    return dict(list(out.items())[:MAX_NOTES])


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
    notes = normalize_notes(raw.get("notes"), raw.get("items"), raw.get("stock"))
    if _note(raw.get("note")):
        notes.setdefault("month", _note(raw.get("note")))
    return {
        "revenue": cell(raw.get("revenue")),
        "items": clean,
        "prepaid": cell(raw.get("prepaid")),
        "actual_paid": cell(raw.get("actual_paid")),
        "invest": cell(raw.get("invest")),
        "stock": normalize_stock(raw.get("stock")),
        "receivable": cell(raw.get("receivable")),     # 외상 매출 (미수금)
        "total_buy": cell(raw.get("total_buy")),       # 총 매입액 (표의 값)
        "notes": notes,
    }


def summary_has_data(sv) -> bool:
    """누적에 쓸 만한 숫자가 하나라도 있는지."""
    if not isinstance(sv, dict):
        return False
    for k in ("revenue", "prepaid", "actual_paid", "invest",
              "receivable", "total_buy"):
        if cell_has(sv.get(k)):
            return True
    for it in sv.get("items") or []:
        if any(cell_has((it or {}).get(m)) for m in METRICS):
            return True
    for r in sv.get("stock") or []:
        if cell_has((r or {}).get("value")):
            return True
    return bool(sv.get("notes"))


def normalize_summary(raw, months=None) -> dict:
    """누적 한 칸. 달 한 칸과 모양이 같고 어느 구간인지만 더 붙는다."""
    raw = raw if isinstance(raw, dict) else {}
    out = normalize_month(raw)
    keys = sorted(months or {})
    a = _month(raw.get("from")) or (keys[0] if keys else "")
    b = _month(raw.get("to")) or (keys[-1] if keys else "")
    out["from"], out["to"] = a, b
    out["label"] = (_s(raw.get("label")) or
                    ("%s~%s 누적" % (month_label(a), month_label(b))
                     if a and b else "누적"))[:MAX_LABEL]
    return out


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
            summary = normalize_summary(body.get("summary"), months)
            if summary_has_data(summary):
                divs[div]["summary"] = summary
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
    notes = mv.get("notes") or {}
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
            "notes": {m: notes.get("item:%s:%s" % (it.get("key", ""), m), "")
                      for m in METRICS},
            "note": "\n".join(t for t in
                              (notes.get("item:%s:%s" % (it.get("key", ""), m), "")
                               for m in METRICS) if t),
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
                      "note": notes.get("stock:%s" % r.get("key", ""), "")})
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
        "notes": dict(notes),
        "note": notes.get("month", ""),
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


def _fill_regions(mv: dict, out: dict) -> dict:
    for c in ([mv.get("revenue"), mv.get("prepaid"), mv.get("actual_paid"),
               mv.get("invest"), mv.get("receivable"), mv.get("total_buy")]
              + [it.get(m) for it in (mv.get("items") or []) for m in METRICS]
              + [r.get("value") for r in (mv.get("stock") or [])]):
        for r in REGIONS:
            if (c or {}).get(r) is not None:
                out[r] = True
    return out


def region_filled(body: dict, scope: str = "all") -> dict:
    """어느 지역이 한 번이라도 적혔는지. 앱이 탭을 흐리게 할 때 쓴다.

    scope="months" 는 달별, "summary" 는 누적만 본다. 이 엑셀은 해외/국내가
    누적에만 있어서, 둘을 뭉쳐 보면 앱이 '해외 탭에 달별 숫자가 있다'고
    잘못 알아듣는다.
    """
    out = {r: False for r in REGIONS}
    if scope in ("all", "months"):
        for mv in (body.get("months") or {}).values():
            _fill_regions(mv, out)
    if scope in ("all", "summary") and isinstance(body.get("summary"), dict):
        _fill_regions(body["summary"], out)
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
    summary = body.get("summary") if isinstance(body.get("summary"), dict) else None
    if summary and summary_has_data(summary):
        total = _resolve(summary, region)
        total["source"] = "sheet"        # 표에 적힌 합계
        a, b = _s(summary.get("from")), _s(summary.get("to"))
        total["range"] = ("%s~%s" % (month_label(a), month_label(b))
                          if a and b else "")
    else:
        total = _sum_months(months)
        total["source"] = "sum"         # 달을 더한 값
        total["range"] = ("%s~%s" % (month_label(keys[0]), month_label(keys[-1]))
                          if keys else "")
    total["month"] = "total"
    total["label"] = "누적"
    total["region"] = region
    total["region_label"] = REGION_LABEL.get(region, region)
    return {
        "division": div,
        "currency": body.get("currency") or "USD",
        "region": region,
        "regions": [{"key": r, "label": REGION_LABEL[r]} for r in REGIONS],
        "regions_filled": region_filled(body),
        "months_regions_filled": region_filled(body, "months"),
        "summary_regions_filled": region_filled(body, "summary"),
        "has_summary": bool(summary and summary_has_data(summary)),
        "has_data": bool(keys) or bool(summary and summary_has_data(summary)),
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
        "summary": (body.get("summary")
                    if isinstance(body.get("summary"), dict) else None),
        "default_items": [{"key": k, "label": l} for k, l in DEFAULT_ITEMS],
        "stock_rows": [{"key": k, "label": l} for k, l in STOCK_ROWS],
        "regions": [{"key": r, "label": REGION_LABEL[r]} for r in REGIONS],
    }


def put_division(data: dict, div: str, payload: dict) -> dict:
    """한 사업부 통째로 갈아끼운다 — 화면이 전체를 들고 있다."""
    out = normalize(data)
    payload = payload if isinstance(payload, dict) else {}
    old_summary = (out.get("divisions") or {}).get(div, {}).get("summary")
    months = payload.get("months") if isinstance(payload.get("months"), dict) else {}
    cur = _s(payload.get("currency")).upper()
    clean = {}
    for m, mv in months.items():
        mk = _month(m)
        if mk:
            clean[mk] = normalize_month(mv)
    out["divisions"][div] = {"currency": cur if cur in CURRENCIES else "USD",
                             "months": clean}
    # 누적은 'summary' 를 보내올 때만 바꾼다. 안 보내면 있던 걸 지키는
    # 쪽이 맞다 — 화면이 안 들고 있는 걸 저장했다가 통째로 날린 적이 있다.
    if "summary" in payload:
        summary = normalize_summary(payload.get("summary"), clean)
        if summary_has_data(summary):
            out["divisions"][div]["summary"] = summary
    elif isinstance(old_summary, dict):
        out["divisions"][div]["summary"] = old_summary
    return out
