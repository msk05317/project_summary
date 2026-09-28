"""사업부 월별 매입·지급 현황.

엑셀 '월별 매입 현황 분석'을 그대로 담는다. 월마다
  매출액 / 항목별(원소재·소모품·기타·외주) 매입·지급·잔액 / 지급내역(선급금·실지급액·실비투자)

잔액은 계산하지 않고 '적힌 값'을 쓴다. 표의 잔액이 매입-지급과 맞지 않는 달이
있기 때문이다(선급금 상계로 보인다). 비워두면 그때만 매입-지급으로 채운다.
"""
from __future__ import annotations

import datetime as _dt
import json
import re
from pathlib import Path

CURRENCIES = ("USD", "KRW")
MAX_MONTHS = 60
MAX_ITEMS = 12
MAX_LABEL = 40

DEFAULT_ITEMS = (
    ("raw", "원소재"),
    ("supply", "소모품"),
    ("etc", "기타 (약품·포장재 등)"),
    ("outsourcing", "외주"),
)

_MONTH_RE = re.compile(r"^20\d\d-(0[1-9]|1[0-2])$")
_KEY_RE = re.compile(r"^[a-z0-9_]{1,24}$")


def _s(v) -> str:
    return "" if v is None else str(v).strip()


def _num(v):
    """빈 칸은 None 으로 남긴다 — 0 과 '안 적음'은 다르다."""
    if v is None:
        return None
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    t = _s(v).replace(",", "").replace("$", "").replace("₩", "")
    if not t:
        return None
    neg = False
    if t.startswith("(") and t.endswith(")"):      # (1,234.5) = 음수
        neg, t = True, t[1:-1].strip()
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


def normalize_item(raw, idx: int) -> dict:
    raw = raw if isinstance(raw, dict) else {}
    dk, dl = DEFAULT_ITEMS[idx] if idx < len(DEFAULT_ITEMS) else ("item%d" % (idx + 1), "항목%d" % (idx + 1))
    return {
        "key": _key(raw.get("key"), dk),
        "label": (_s(raw.get("label")) or dl)[:MAX_LABEL],
        "buy": _num(raw.get("buy")),
        "paid": _num(raw.get("paid")),
        "balance": _num(raw.get("balance")),
    }


def normalize_month(raw) -> dict:
    raw = raw if isinstance(raw, dict) else {}
    items_raw = raw.get("items")
    if not isinstance(items_raw, list) or not items_raw:
        items_raw = [{"key": k, "label": l} for k, l in DEFAULT_ITEMS]
    items = [normalize_item(it, i) for i, it in enumerate(items_raw[:MAX_ITEMS])]
    seen, out = set(), []
    for it in items:
        k = it["key"]
        while k in seen:
            k += "_"
        it["key"] = k[:24]
        seen.add(it["key"])
        out.append(it)
    return {
        "revenue": _num(raw.get("revenue")),
        "items": out,
        "prepaid": _num(raw.get("prepaid")),
        "actual_paid": _num(raw.get("actual_paid")),
        "invest": _num(raw.get("invest")),
        "note": _s(raw.get("note"))[:300],
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
            divs[div] = {
                "currency": cur if cur in CURRENCIES else "USD",
                "months": months,
            }
    return {"version": 1, "updated_at": _s(data.get("updated_at")), "divisions": divs}


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


# ---------------------------------------------------------------- 보기


def _resolve(mv: dict) -> dict:
    """한 달치를 앱이 그릴 수 있는 형태로 푼다."""
    items = []
    buy = paid = bal = 0.0
    for it in mv.get("items") or []:
        b, p = _f(it.get("buy")), _f(it.get("paid"))
        raw_bal = it.get("balance")
        r = b - p if raw_bal is None else float(raw_bal)
        # 세 칸이 다 0인 항목은 앱에서 빼 준다. PCB 의 '조립자재' 처럼
        # 표에는 줄이 있지만 값이 없는 항목이 화면 자리만 차지했다.
        # (admin 은 for_admin 으로 원본을 받으니 입력 칸은 그대로 있다)
        if b == 0 and p == 0 and r == 0:
            continue
        items.append({
            "key": it.get("key", ""),
            "label": it.get("label", ""),
            "buy": b, "paid": p, "balance": r,
            "balance_auto": raw_bal is None,
            "pay_rate": round(p / b * 100, 1) if b > 0 else 0.0,
        })
        buy += b
        paid += p
        bal += r
    rev = _f(mv.get("revenue"))
    prepaid, actual = _f(mv.get("prepaid")), _f(mv.get("actual_paid"))
    invest = mv.get("invest")
    return {
        "revenue": rev,
        "buy": buy, "paid": paid, "balance": bal,
        "pay_rate": round(paid / buy * 100, 1) if buy > 0 else 0.0,
        "items": items,
        "payment": {
            "prepaid": prepaid,
            "actual_paid": actual,
            "invest": None if invest is None else float(invest),
            "total": prepaid + actual + (0.0 if invest is None else float(invest)),
        },
        "note": mv.get("note", ""),
    }


def _empty_total(months: list) -> dict:
    tot = {"revenue": 0.0, "buy": 0.0, "paid": 0.0, "balance": 0.0}
    labels, keys = {}, []
    pay = {"prepaid": 0.0, "actual_paid": 0.0, "invest": None, "total": 0.0}
    acc = {}
    for m in months:
        for k in ("revenue", "buy", "paid", "balance"):
            tot[k] += m[k]
        for it in m["items"]:
            k = it["key"]
            if k not in acc:
                acc[k] = {"key": k, "label": it["label"], "buy": 0.0, "paid": 0.0,
                          "balance": 0.0, "balance_auto": True, "pay_rate": 0.0}
                keys.append(k)
            labels[k] = it["label"]
            acc[k]["buy"] += it["buy"]
            acc[k]["paid"] += it["paid"]
            acc[k]["balance"] += it["balance"]
        p = m["payment"]
        pay["prepaid"] += p["prepaid"]
        pay["actual_paid"] += p["actual_paid"]
        if p["invest"] is not None:
            pay["invest"] = (pay["invest"] or 0.0) + p["invest"]
    for k in keys:
        a = acc[k]
        a["label"] = labels[k]
        a["pay_rate"] = round(a["paid"] / a["buy"] * 100, 1) if a["buy"] > 0 else 0.0
    pay["total"] = pay["prepaid"] + pay["actual_paid"] + (pay["invest"] or 0.0)
    tot["pay_rate"] = round(tot["paid"] / tot["buy"] * 100, 1) if tot["buy"] > 0 else 0.0
    tot["items"] = [acc[k] for k in keys]
    tot["payment"] = pay
    tot["note"] = ""
    return tot


def month_label(m: str) -> str:
    try:
        return "%d월" % int(m[5:7])
    except Exception:
        return m


def for_app(data: dict, div: str) -> dict:
    """앱 카드 한 장이 필요한 전부. 월이 적어도 12개를 넘지 않는다."""
    body = (data.get("divisions") or {}).get(div) or {}
    months_raw = body.get("months") or {}
    keys = sorted(months_raw)[-12:]
    months = []
    for m in keys:
        v = _resolve(months_raw[m])
        v["month"] = m
        v["label"] = month_label(m)
        months.append(v)
    total = _empty_total(months)
    total["month"] = "total"
    total["label"] = "누적"
    if keys:
        total["range"] = "%s~%s" % (month_label(keys[0]), month_label(keys[-1]))
    else:
        total["range"] = ""
    return {
        "division": div,
        "currency": body.get("currency") or "USD",
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
    out["divisions"][div] = {
        "currency": cur if cur in CURRENCIES else "USD",
        "months": clean,
    }
    return out
