"""전사 사업부별 잔업·특근 현황.

매입 현황과 다르게 **주 단위**다. 엑셀이 W39(9/21~9/27) 처럼 한 주씩
들어오고, 사업부 시트에는 요일별 값이 있다. 그래서 담는 모양도

    사업부 → 주차(2026-W39) → 요일(mon…sun)

이다. 월로 접으면 요일을 잃는데, 요일이 이 자료의 핵심이다 —
평일은 '잔업', 일요일은 '특근'으로 아예 다른 지표다.

지표가 하나가 아니다.
  - 잔업률  : 월~토. 일요일 칸은 'X' (해당 없음)
  - 특근률  : 일요일.  평일 칸은 'X' (해당 없음)
각각 전체 / 직접 / 간접으로 또 갈린다.

'X' 를 0 으로 바꾸면 안 된다. 0 은 '아무도 안 나왔다', X 는 '그 날은
이 지표가 없다' 이다. 평균을 낼 때 X 를 0 으로 세면 잔업률이 6/7 로
줄어든다. 그래서 None 으로 두고, 평균에서 아예 뺀다.

비율은 저장한 값을 그대로 쓰지 않고 인원으로 다시 낸다 —
    잔업률 = Σ잔업인원(월~토) / Σ가용인원(월~토)
엑셀의 합계 줄과 대조해 보면 이 방식이 맞다 (PCB 107.5/441 = 24.4%).
전사도 같은 식의 가중평균이다 (8,727/12,485 = 69.9%).
"""
from __future__ import annotations

import datetime as _dt
import json
import re
from decimal import Decimal as _D, ROUND_HALF_UP as _HALF_UP
from pathlib import Path

DAYS = ("mon", "tue", "wed", "thu", "fri", "sat", "sun")
DAY_LABEL = {"mon": "월", "tue": "화", "wed": "수", "thu": "목",
             "fri": "금", "sat": "토", "sun": "일"}
WEEKDAYS = DAYS[:6]          # 잔업
SUNDAY = "sun"               # 특근

KINDS = ("overtime", "special")
KIND_LABEL = {"overtime": "잔업", "special": "특근"}
KIND_RANGE = {"overtime": "월~토", "special": "일"}
SCOPES = ("total", "direct", "indirect")
SCOPE_LABEL = {"total": "전체", "direct": "직접", "indirect": "간접"}

MAX_WEEKS = 120
MAX_DIVS = 60
MAX_NOTE = 600
MAX_LABEL = 40

_WEEK_RE = re.compile(r"^20\d\d-W(0[1-9]|[1-4]\d|5[0-3])$")
# 사업부 키는 엑셀 시트 이름에서 온다 — 대부분 한글이다. 영문만 받으면
# 16개 중 3개(pcb·ess·press)만 남고 나머지가 조용히 사라진다.
_KEY_RE = re.compile(r"^[0-9a-z가-힣_]{1,32}$")

CHECK_OK = "OK"
CHECK_WARN = "확인필요"


def _s(v) -> str:
    return "" if v is None else str(v).strip()


def _note(v) -> str:
    t = "" if v is None else str(v)
    t = t.replace("\r\n", "\n").replace("\r", "\n")
    lines = [ln.rstrip() for ln in t.split("\n")]
    while lines and not lines[0]:
        lines.pop(0)
    while lines and not lines[-1]:
        lines.pop()
    return "\n".join(lines)[:MAX_NOTE]


def num(v):
    """빈 칸과 'X' 는 None. 0 과 구별해야 한다."""
    if v is None or isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    t = _s(v).replace(",", "").replace("%", "")
    if not t or t in ("-", "—", "–") or t.upper() == "X":
        return None
    neg = False
    if t.startswith("(") and t.endswith(")"):
        neg, t = True, t[1:-1].strip()
    try:
        f = float(t)
    except ValueError:
        return None
    return -f if neg else f


def week_key(v) -> str:
    t = _s(v).upper().replace(" ", "")
    return t if _WEEK_RE.match(t) else ""


def week_of(year: int, w: int) -> str:
    return "%04d-W%02d" % (int(year), int(w))


def week_label(wk: str) -> str:
    return wk[5:] if _WEEK_RE.match(_s(wk)) else _s(wk)


def div_key(v, fallback: str = "") -> str:
    t = _s(v).lower()
    return t if _KEY_RE.match(t) else fallback


# ── 한 요일 ───────────────────────────────────────────────────


def _people(raw, keys) -> dict:
    raw = raw if isinstance(raw, dict) else {}
    return {k: num(raw.get(k)) for k in keys}


def normalize_day(raw) -> dict:
    """요일 한 칸. 없는 값은 None 으로 남긴다."""
    raw = raw if isinstance(raw, dict) else {}
    out = {
        "headcount": _people(raw.get("headcount"), ("total", "day", "night")),
        "support": _people(raw.get("support"), ("in", "out")),
        "available": _people(raw.get("available"), ("total", "day", "night")),
        "direct": _people(raw.get("direct"), ("total", "day", "night")),
        "indirect": _people(raw.get("indirect"), ("total", "day", "night")),
    }
    for kind in KINDS:
        k = raw.get(kind) if isinstance(raw.get(kind), dict) else {}
        out[kind] = {"people": _people(k.get("people"), SCOPES)}
    return out


def day_has(d: dict) -> bool:
    return any(v is not None for v in (d.get("available") or {}).values()) \
        or any(v is not None
               for kind in KINDS
               for v in ((d.get(kind) or {}).get("people") or {}).values())


def normalize_division(raw) -> dict:
    raw = raw if isinstance(raw, dict) else {}
    days_raw = raw.get("days") if isinstance(raw.get("days"), dict) else {}
    days = {}
    for d in DAYS:
        one = normalize_day(days_raw.get(d))
        if day_has(one):
            days[d] = one
    check = _s(raw.get("check"))
    return {
        "label": (_s(raw.get("label")) or "")[:MAX_LABEL],
        "days": days,
        "note": _note(raw.get("note")),
        "check": check if check in (CHECK_OK, CHECK_WARN) else "",
    }


def normalize_week(raw) -> dict:
    raw = raw if isinstance(raw, dict) else {}
    divs_raw = raw.get("divisions") if isinstance(raw.get("divisions"), dict) else {}
    divs = {}
    for k, v in list(divs_raw.items())[:MAX_DIVS]:
        key = div_key(k)
        if key:
            divs[key] = normalize_division(v)
    return {
        "range": _s(raw.get("range"))[:MAX_LABEL],   # "9/21~9/27"
        "source": _s(raw.get("source"))[:120],       # 올린 파일 이름
        "divisions": divs,
        "issues": [_note(x)[:200] for x in (raw.get("issues") or [])
                   if _note(x)][:40],               # 확인사항 시트
    }


def normalize(data) -> dict:
    data = data if isinstance(data, dict) else {}
    weeks_raw = data.get("weeks") if isinstance(data.get("weeks"), dict) else {}
    weeks = {}
    for w, wv in weeks_raw.items():
        wk = week_key(w)
        if wk:
            weeks[wk] = normalize_week(wv)
    if len(weeks) > MAX_WEEKS:
        for wk in sorted(weeks)[:-MAX_WEEKS]:
            weeks.pop(wk, None)
    order = [div_key(x) for x in (data.get("order") or []) if div_key(x)]
    return {"version": 1, "updated_at": _s(data.get("updated_at")),
            "order": order, "weeks": weeks}


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


# ── 집계 ─────────────────────────────────────────────────────


def _r(x, nd=0):
    """엑셀의 ROUND 와 같게 — 0.5 는 올린다.

    파이썬 기본 round() 는 은행가 반올림이라 164.5 를 164 로 내린다.
    사업부마다 1명씩 어긋나면 전사 합계가 엑셀과 안 맞고, 그러면
    보는 사람이 어느 쪽을 믿어야 할지 모른다.
    """
    q = _D(1) if nd <= 0 else _D(1).scaleb(-nd)
    v = _D(repr(float(x))).quantize(q, rounding=_HALF_UP)
    return int(v) if nd <= 0 else float(v)


def _rate(top, bottom):
    if not bottom:
        return None
    return _r(top / bottom, 4)


def _kind_days(kind: str) -> tuple:
    return WEEKDAYS if kind == "overtime" else (SUNDAY,)


def division_week(div: dict) -> dict:
    """사업부 한 주. 인원은 요일 평균, 비율은 인원 합으로 다시 낸다."""
    days = div.get("days") or {}
    have = [d for d in DAYS if d in days]

    def avg(path):
        vals = []
        for d in have:
            cur = days[d]
            for step in path:
                cur = (cur or {}).get(step)
            if cur is not None:
                vals.append(float(cur))
        return _r(sum(vals) / len(vals)) if vals else None

    head = {k: avg(("headcount", k)) for k in ("total", "day", "night")}
    sup = {k: avg(("support", k)) for k in ("in", "out")}
    avail = {k: avg(("available", k)) for k in ("total", "day", "night")}
    direct = {k: avg(("direct", k)) for k in ("total", "day", "night")}
    indirect = {k: avg(("indirect", k)) for k in ("total", "day", "night")}
    night_rate = _rate(avail.get("night") or 0, avail.get("total") or 0)

    base = {"total": avail.get("total"), "direct": direct.get("total"),
            "indirect": indirect.get("total")}

    out_kinds = {}
    for kind in KINDS:
        ds = [d for d in _kind_days(kind) if d in days]
        people, rate, day_rate = {}, {}, {}
        for sc in SCOPES:
            tot, bot, n = 0.0, 0.0, 0
            for d in ds:
                p = ((days[d].get(kind) or {}).get("people") or {}).get(sc)
                if p is None:
                    continue
                b = _scope_base(days[d], sc)
                tot += float(p)
                n += 1
                if b:
                    bot += float(b)
            people[sc] = _r(tot / n) if n else None
            rate[sc] = _rate(tot, bot) if n else None
        for d in ds:
            p = ((days[d].get(kind) or {}).get("people") or {}).get("total")
            b = _scope_base(days[d], "total")
            day_rate[d] = _rate(float(p), float(b)) if (p is not None and b) else None
        out_kinds[kind] = {"label": KIND_LABEL[kind], "range": KIND_RANGE[kind],
                           "people": people, "rate": rate, "by_day": day_rate}

    return {
        "label": div.get("label", ""),
        "headcount": head, "support": sup, "available": avail,
        "direct": direct, "indirect": indirect, "night_rate": night_rate,
        "base": base,
        "overtime": out_kinds["overtime"], "special": out_kinds["special"],
        "note": div.get("note", ""), "check": div.get("check", ""),
        "days": [d for d in DAYS if d in days],
        "has_data": bool(have),
    }


def _scope_base(day: dict, scope: str):
    if scope == "direct":
        return (day.get("direct") or {}).get("total")
    if scope == "indirect":
        return (day.get("indirect") or {}).get("total")
    return (day.get("available") or {}).get("total")


def _sum_div(rows: list) -> dict:
    """전사. 사업부 값을 평균 내지 않고 인원을 더해서 다시 나눈다 —
    인원이 30명인 곳과 3,000명인 곳을 같은 무게로 세면 안 된다."""
    def add(path):
        tot, any_ = 0.0, False
        for r in rows:
            cur = r
            for step in path:
                cur = (cur or {}).get(step)
            if cur is not None:
                tot += float(cur)
                any_ = True
        return _r(tot) if any_ else None

    head = {k: add(("headcount", k)) for k in ("total", "day", "night")}
    sup = {k: add(("support", k)) for k in ("in", "out")}
    avail = {k: add(("available", k)) for k in ("total", "day", "night")}
    direct = {k: add(("direct", k)) for k in ("total", "day", "night")}
    indirect = {k: add(("indirect", k)) for k in ("total", "day", "night")}

    out = {}
    for kind in KINDS:
        people, rate = {}, {}
        for sc in SCOPES:
            p = add((kind, "people", sc))
            b = {"total": avail.get("total"), "direct": direct.get("total"),
                 "indirect": indirect.get("total")}.get(sc)
            people[sc] = p
            rate[sc] = _rate(float(p), float(b)) if (p is not None and b) else None
        out[kind] = {"label": KIND_LABEL[kind], "range": KIND_RANGE[kind],
                     "people": people, "rate": rate, "by_day": {}}
    return {
        "label": "전체", "headcount": head, "support": sup, "available": avail,
        "direct": direct, "indirect": indirect,
        "night_rate": _rate(avail.get("night") or 0, avail.get("total") or 0),
        "overtime": out["overtime"], "special": out["special"],
        "note": "", "check": "", "days": [], "has_data": bool(rows),
    }


# ── 검산 ─────────────────────────────────────────────────────
#
# 엑셀에도 '일치확인' 열이 있지만 그 값을 믿지 않고 우리가 다시 센다.
# W39 는 파일이 OK 라고 한 네트워크에서 '일요일 주간+야간이 가용보다 4명
# 적다' 가 하나 더 나왔다.
#
# 반드시 **요일 원본값**으로 센다. 주 평균으로 세면 요일마다 따로 반올림한
# 차이 때문에 멀쩡한 사업부가 1명씩 틀린 것처럼 나온다 (W39 에서 시스템·
# 헬스케어·자동차휠 셋이 그랬다).
AUDITS = (
    ("avail_shift", "주간+야간 ≠ 가용", ("available", "day"), ("available", "night"),
     ("available", "total")),
    ("avail_kind", "직접+간접 ≠ 가용", ("direct", "total"), ("indirect", "total"),
     ("available", "total")),
    ("overtime_kind", "잔업 직접+간접 ≠ 전체",
     ("overtime", "people", "direct"), ("overtime", "people", "indirect"),
     ("overtime", "people", "total")),
    ("special_kind", "특근 직접+간접 ≠ 전체",
     ("special", "people", "direct"), ("special", "people", "indirect"),
     ("special", "people", "total")),
)


def _dig(day: dict, path):
    cur = day
    for step in path:
        cur = (cur or {}).get(step)
    return cur


def audit_division(div: dict) -> list:
    """한 사업부의 안 맞는 곳. 없으면 빈 리스트."""
    days = (div or {}).get("days") or {}
    out = []
    for code, label, a, b, total in AUDITS:
        hits = []
        for d in DAYS:
            one = days.get(d)
            if not one:
                continue
            av, bv, tv = _dig(one, a), _dig(one, b), _dig(one, total)
            if None in (av, bv, tv):
                continue
            gap = round(float(av) + float(bv) - float(tv), 3)
            if gap:
                hits.append((d, gap))
        if not hits:
            continue
        gaps = [g for _, g in hits]
        lo, hi = min(gaps), max(gaps)
        span = ("%+g명" % lo) if lo == hi else ("%+g~%+g명" % (lo, hi))
        out.append({
            "code": code, "label": label,
            "days": [d for d, _ in hits],
            "day_labels": "".join(DAY_LABEL[d] for d, _ in hits),
            "min": lo, "max": hi,
            "text": "%s (%s · %s)" % (label, "".join(DAY_LABEL[d] for d, _ in hits), span),
        })
    return out


def _delta(now, before):
    if now is None or before is None:
        return None
    return _r(now - before, 4)


def _order_of(data: dict, wk: str) -> list:
    week = (data.get("weeks") or {}).get(wk) or {}
    keys = list((week.get("divisions") or {}).keys())
    pref = [k for k in (data.get("order") or []) if k in keys]
    return pref + [k for k in keys if k not in pref]


def prev_week(data: dict, wk: str) -> str:
    earlier = sorted(w for w in (data.get("weeks") or {}) if w < wk)
    return earlier[-1] if earlier else ""


def for_app(data: dict, wk: str = "", kind: str = "overtime",
            scope: str = "total") -> dict:
    """전사 화면 한 판. 주차 하나, 지표 하나, 범위 하나."""
    kind = kind if kind in KINDS else "overtime"
    scope = scope if scope in SCOPES else "total"
    weeks = sorted(data.get("weeks") or {})
    wk = week_key(wk) or (weeks[-1] if weeks else "")
    week = (data.get("weeks") or {}).get(wk) or {}
    prev = prev_week(data, wk)
    pweek = (data.get("weeks") or {}).get(prev) or {}

    rows, before = [], {}
    for k in _order_of(data, prev):
        before[k] = division_week((pweek.get("divisions") or {})[k])
    for k in _order_of(data, wk):
        rows.append((k, division_week((week.get("divisions") or {})[k])))

    total = _sum_div([r for _, r in rows])
    ptotal = _sum_div(list(before.values())) if before else None
    avg = (total.get(kind) or {}).get("rate", {}).get(scope)

    items = []
    for k, r in rows:
        v = (r.get(kind) or {}).get("rate", {}).get(scope)
        b = ((before.get(k) or {}).get(kind) or {}).get("rate", {}).get(scope) \
            if k in before else None
        # 지표(잔업/특근) × 범위(전체/직접/간접) 여섯 칸을 한 번에 내려보낸다.
        # 앱에서 토글할 때마다 서버를 다시 부르면 매번 로딩이 돌아서, 화면이
        # 끊긴다. 한 사업부당 열여덟 개 숫자라 무게도 거의 없다.
        rates, deltas, people = {}, {}, {}
        for kd in KINDS:
            rates[kd], deltas[kd], people[kd] = {}, {}, {}
            for sc in SCOPES:
                now = (r.get(kd) or {}).get("rate", {}).get(sc)
                was = ((before.get(k) or {}).get(kd) or {}).get("rate", {}).get(sc) \
                    if k in before else None
                rates[kd][sc] = now
                deltas[kd][sc] = _delta(now, was)
                people[kd][sc] = (r.get(kd) or {}).get("people", {}).get(sc)
        items.append({
            "key": k, "label": r.get("label") or k,
            "rate": v, "delta": _delta(v, b),
            "people": (r.get(kind) or {}).get("people", {}).get(scope),
            "available": (r.get("available") or {}).get("total"),
            "over_avg": bool(v is not None and avg is not None and v > avg),
            "rates": rates, "deltas": deltas, "people_by": people,
            "note": r.get("note", ""), "check": r.get("check", ""),
            "audit": [x["text"] for x in
                      audit_division((week.get("divisions") or {}).get(k) or {})],
        })
    rated = [x for x in items if x["rate"] is not None]
    rated.sort(key=lambda x: x["rate"], reverse=True)
    items = rated + [x for x in items if x["rate"] is None]

    pavg = ((ptotal or {}).get(kind) or {}).get("rate", {}).get(scope) \
        if ptotal else None
    return {
        "week": wk, "week_label": week_label(wk), "range": week.get("range", ""),
        "prev_week": prev, "prev_label": week_label(prev) if prev else "",
        "kind": kind, "kind_label": KIND_LABEL[kind], "kind_range": KIND_RANGE[kind],
        "scope": scope, "scope_label": SCOPE_LABEL[scope],
        "kinds": [{"key": k, "label": KIND_LABEL[k], "range": KIND_RANGE[k]}
                  for k in KINDS],
        "scopes": [{"key": s, "label": SCOPE_LABEL[s]} for s in SCOPES],
        "weeks": weeks,
        "total": total,
        # 앱 홈 카드가 잔업·특근 두 지표의 증감을 같이 보여 준다. 전주 합계를
        # 같이 주면 화면이 뺄셈 한 번으로 끝낸다 — 집계를 다시 하지 않는다.
        "prev_total": ptotal,
        "avg": avg, "avg_prev": pavg, "avg_delta": _delta(avg, pavg),
        "counts": {
            "divisions": len(items),
            "over": sum(1 for x in items if x["over_avg"]),
            "under": sum(1 for x in items
                         if x["rate"] is not None and not x["over_avg"]),
            "up": sum(1 for x in items if (x["delta"] or 0) > 0),
            "down": sum(1 for x in items if (x["delta"] or 0) < 0),
            "check": sum(1 for x in items if x["check"] == CHECK_WARN),
            "audit": sum(1 for x in items if x["audit"]),
        },
        "items": items,
        "issues": week.get("issues") or [],
        "has_data": bool(items),
    }


def for_division(data: dict, key: str, wk: str = "") -> dict:
    """사업부 한 곳 — 요일별까지."""
    key = div_key(key)
    weeks = sorted(data.get("weeks") or {})
    wk = week_key(wk) or (weeks[-1] if weeks else "")
    week = (data.get("weeks") or {}).get(wk) or {}
    raw = (week.get("divisions") or {}).get(key)
    if raw is None:
        return {"division": key, "week": wk, "has_data": False}
    cur = division_week(raw)
    prev = prev_week(data, wk)
    praw = (((data.get("weeks") or {}).get(prev) or {})
            .get("divisions") or {}).get(key)
    before = division_week(praw) if praw else None

    deltas = {}
    for kind in KINDS:
        deltas[kind] = {
            sc: _delta((cur.get(kind) or {}).get("rate", {}).get(sc),
                       ((before or {}).get(kind) or {}).get("rate", {}).get(sc)
                       if before else None)
            for sc in SCOPES}

    by_day = []
    for d in DAYS:
        if d not in (raw.get("days") or {}):
            continue
        kind = "special" if d == SUNDAY else "overtime"
        by_day.append({
            "day": d, "label": DAY_LABEL[d], "kind": kind,
            "kind_label": KIND_LABEL[kind],
            "rate": (cur.get(kind) or {}).get("by_day", {}).get(d),
            "people": (((raw["days"][d].get(kind) or {})
                        .get("people") or {}).get("total")),
            "available": (raw["days"][d].get("available") or {}).get("total"),
        })

    return {"division": key, "week": wk, "week_label": week_label(wk),
            "range": week.get("range", ""),
            "prev_week": prev, "prev_label": week_label(prev) if prev else "",
            "summary": cur, "deltas": deltas, "by_day": by_day,
            "has_data": True}


def for_admin(data: dict, wk: str = "") -> dict:
    """관리 화면 한 판 — 고칠 원본과, 보여 줄 집계를 같이 준다.

    집계를 화면에서 다시 계산하게 두면 앱과 숫자가 갈린다. 가중평균과
    반올림 규칙이 한 군데에만 있어야 한다.
    """
    weeks = sorted(data.get("weeks") or {})
    wk = week_key(wk) or (weeks[-1] if weeks else "")
    week = (data.get("weeks") or {}).get(wk) or {}
    divs = week.get("divisions") or {}
    order = _order_of(data, wk)

    rows, rolled = [], []
    for k in order:
        raw = divs[k]
        one = division_week(raw)
        rolled.append(one)
        audit = audit_division(raw)
        rows.append(dict(one, key=k, audit=audit, audit_count=len(audit)))
    total = _sum_div(rolled)

    return {"week": wk, "weeks": weeks, "range": week.get("range", ""),
            "source": week.get("source", ""),
            "order": order,
            "divisions": divs,              # 고칠 원본 (요일별 날 것)
            "rows": rows, "total": total,   # 보여 줄 집계
            "issues": week.get("issues") or [],
            "audit_count": sum(r["audit_count"] for r in rows),
            "days": [{"key": d, "label": DAY_LABEL[d]} for d in DAYS],
            "weekdays": list(WEEKDAYS), "sunday": SUNDAY,
            "kinds": [{"key": k, "label": KIND_LABEL[k], "range": KIND_RANGE[k]}
                      for k in KINDS],
            "scopes": [{"key": s, "label": SCOPE_LABEL[s]} for s in SCOPES]}


def put_week(data: dict, wk: str, payload: dict) -> dict:
    """주차 하나를 통째로 갈아끼운다. 다른 주는 건드리지 않는다."""
    out = normalize(data)
    key = week_key(wk)
    if not key:
        raise ValueError("주차는 2026-W39 처럼 적어 주세요.")
    out["weeks"][key] = normalize_week(payload)
    order = [div_key(x) for x in ((payload or {}).get("order") or []) if div_key(x)]
    if order:
        seen = list(out.get("order") or [])
        out["order"] = order + [k for k in seen if k not in order]
    return out
