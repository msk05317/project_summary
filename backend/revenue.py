# 사업부 매출 — 주간보고 엑셀이 원본이다.
#
# 모델 판가 × 수량으로 계산하던 것을 그만둔다. 판가는 추정이고, 실제로
# 하바플레이트 55종 중 52종이 3,400 으로 일괄 입력돼 있어서 9월 매출이
# 18만 달러 부풀어 있었다. 확정 금액은 이미 주간보고에 있다.
#
#   '1. 계획 대비 실적 (수정본) Actual FCST' 시트 한 장에
#     · 줄마다 사업계획 / 실행계획 / Open PO / 실적
#     · 열마다 W1 ~ W52
#     · 맨 아래 [합 계] 블록에 보고서 묶음이 그대로
#
#         매출합계 (Revenue)   반도체 / 데이터 센터 / 우주항공 → 소계
#         내부거래 (Internal)  구미/화성/미국
#         총합 (내부거래 포함) = 소계 + 내부거래
#
# 묶음 합계는 [합 계] 블록을 그대로 쓴다. 세부를 우리가 더해서 만들면
# 파일이 말한 값과 어긋날 수 있고, 어긋나도 아무도 모른다. 세부는 따로
# 읽어서 합이 맞는지 대조만 한다.
import datetime as _dt
import io
import json
import re
import threading as _threading

# [합 계] 블록의 줄 이름 → 묶음 키
GROUPS = [("semi", "반도체 (SEMI)"),
          ("dc", "데이터 센터 (Data Center)"),
          ("space", "우주항공 (Space X)")]
INTERNAL = ("internal", "구미/화성/미국 (Gumi/Hwaseong/USA/YONGIN)")
GROUP_LABEL = dict(GROUPS + [INTERNAL])
ORDER = ["semi", "dc", "space", "internal"]


def norm(s) -> str:
    """줄바꿈·겹공백을 없앤 이름. 엑셀은 같은 줄을 파일마다 다르게 접는다."""
    return " ".join(str(s or "").split())


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


def _sheet(wb):
    for ws in wb.worksheets:
        t = norm(ws.title)
        if "계획 대비 실적" in t and "FCST" in t.upper():
            return ws
    for ws in wb.worksheets:
        if "계획 대비 실적" in norm(ws.title):
            return ws
    return wb.worksheets[0]


def _group_of(div: str, cust: str) -> str:
    """세부 한 줄이 어느 묶음인지.

    엑셀은 사업부 칸을 한 번만 적고 아래로 이어 쓴다. 그래서 텍슨
    사이트 줄들이 '우주항공' 아래에 붙어 있는데, 실제로는 내부거래다
    (합계로 검산해 보면 425,502 + 32,062,096 = 32,487,598 로 맞는다).
    """
    d, c = norm(div), norm(cust)
    if "Texon" in c or "Seojin" in c:
        return "internal"
    if d.startswith("반도체"):
        return "semi"
    if "네트워크" in d or "데이터" in c:
        return "dc"
    if "우주항공" in d or "스페이스" in c:
        return "space"
    return "semi"


def parse_weekly(raw: bytes, year_hint: int = None) -> dict:
    """주간보고 시트 한 장에서 주차별 계획·실적을 꺼낸다."""
    wb = _open(raw)
    ws = _sheet(wb)
    grid = list(ws.iter_rows(values_only=True))

    # 주차 머리 줄 찾기 (W1 · W2 … 가 여럿 있는 줄)
    hi = -1
    for i, r in enumerate(grid[:12]):
        got = sum(1 for v in r if re.fullmatch(r"W\d{1,2}", norm(v)))
        if got >= 2:
            hi = i
            break
    if hi < 0:
        raise ValueError("W1 · W2 … 주차 머리 줄을 못 찾았습니다.")

    # 월은 한 줄 위에 한 번만 적혀 있고 아래로 이어진다
    mrow = grid[hi - 1] if hi > 0 else ()
    wcol, month_of, cur = {}, {}, ""
    for j, v in enumerate(grid[hi]):
        lab = norm(mrow[j]) if j < len(mrow) else ""
        if lab and "월" in lab:
            cur = lab
        w = norm(v)
        if re.fullmatch(r"W\d{1,2}", w):
            wcol[w] = j
            month_of[w] = cur
    weeks = sorted(wcol, key=lambda w: int(w[1:]))

    year = year_hint or _dt.date.today().year
    for r in grid[:6]:
        for v in r:
            m = re.search(r"(20\d\d)\s*년", norm(v))
            if m:
                year = int(m.group(1))
                break

    def months():
        out = {}
        for w in weeks:
            lab = month_of.get(w) or ""
            m = re.search(r"(\d{1,2})\s*월", lab)
            if not m:
                continue
            out.setdefault("%04d-%02d" % (year, int(m.group(1))), []).append(w)
        return out

    # ── 줄 읽기 ───────────────────────────────────────────
    def take(i):
        """i 줄부터 시작하는 한 덩이 (사업계획 / 실행계획 / 실적)."""
        got = {}
        for k in range(i, min(i + 6, len(grid))):
            lab = norm(grid[k][5] if len(grid[k]) > 5 else "")
            if k > i and lab == "사업계획":
                break
            if lab in ("사업계획", "실행계획", "실적"):
                got[lab] = grid[k]
        return got

    def series(row):
        return {w: _num(row[wcol[w]]) if wcol[w] < len(row) else 0.0
                for w in weeks}

    lines, totals = [], {}
    div = cust = ""
    head_at = -1
    for i, r in enumerate(grid):
        c2 = norm(r[2] if len(r) > 2 else "")
        c3 = norm(r[3] if len(r) > 3 else "")
        c4 = norm(r[4] if len(r) > 4 else "")
        c5 = norm(r[5] if len(r) > 5 else "")
        if c2 and "합" in c2 and "계" in c2 and len(c2) <= 6:
            head_at = i                      # [합 계] 부터는 묶음 합계
        if c2:
            div, cust = c2, ""
        if c3:
            cust = c3
        if c5 != "사업계획":
            continue
        blk = take(i)
        if "실적" not in blk:
            continue
        name = c4 or c3 or c2
        vals = {k: series(blk[k]) for k in ("사업계획", "실행계획", "실적")
                if k in blk}
        rec = {"label": name,
               "budget": vals.get("사업계획", {}),
               "plan": vals.get("실행계획", {}),
               "actual": vals.get("실적", {})}
        if head_at >= 0 and i > head_at:
            key = _total_key(c2, c3)
            if key:
                totals[key] = rec
            continue
        rec["div"] = div
        rec["cust"] = cust
        rec["group"] = _group_of(div, cust)
        lines.append(rec)

    if not totals:
        raise ValueError("[합 계] 블록을 못 찾았습니다.")
    return {"year": year, "weeks": weeks, "months": months(),
            "totals": totals, "lines": lines}


def _total_key(c2: str, c3: str) -> str:
    """[합 계] 블록의 줄 이름 → 키."""
    t = norm(c3) or norm(c2)
    if t.startswith("반도체"):
        return "semi"
    if "데이터" in t:
        return "dc"
    if "우주항공" in t or "Space X" in t:
        return "space"
    if t.lower().startswith("sub-total") or t == "소계":
        return "subtotal"
    if "구미" in t and "화성" in t:
        return "internal"
    if norm(c2).startswith("총합"):
        return "grand"
    return ""


# ── 저장 ──────────────────────────────────────────────────
def blank() -> dict:
    return {"version": 2, "updated_at": None, "years": {}, "sources": {}}


class RevenueFileBroken(Exception):
    """파일이 있는데 못 읽는다. 빈 값으로 갈아엎으면 안 된다."""


def load(path) -> dict:
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
    return d


_SAVE_LOCK = _threading.Lock()


def save(path, store: dict) -> None:
    """같은 이름의 임시 파일을 여럿이 동시에 쓰면 서로를 덮어쓴다."""
    import os
    store["updated_at"] = _dt.datetime.now().isoformat(timespec="seconds")
    tmp = "%s.%d.%d.tmp" % (path, os.getpid(), _threading.get_ident())
    with _SAVE_LOCK:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(store, f, ensure_ascii=False, indent=1)
        os.replace(tmp, path)


def apply_weekly(store: dict, parsed: dict, filename: str = "") -> dict:
    """그 해를 통째로 갈아 끼운다. 파일 한 장이 한 해 전체다."""
    y = str(parsed.get("year"))
    before = _grand(store, y)
    store.setdefault("years", {})[y] = {
        "weeks": parsed.get("weeks") or [],
        "months": parsed.get("months") or {},
        "totals": parsed.get("totals") or {},
        "lines": parsed.get("lines") or [],
    }
    store.setdefault("sources", {})["weekly"] = {
        "file": filename,
        "at": _dt.datetime.now().isoformat(timespec="seconds"),
        "year": y,
        "weeks": len(parsed.get("weeks") or []),
        "lines": len(parsed.get("lines") or []),
    }
    return {"year": y, "before": before, "after": _grand(store, y)}


def _grand(store: dict, year: str) -> int:
    got = ((store.get("years") or {}).get(str(year)) or {})
    rec = (got.get("totals") or {}).get("grand") or {}
    return round(sum((rec.get("actual") or {}).values()))


def _months_of(y: dict, month: str) -> list:
    return list((y.get("months") or {}).get(month) or [])


def _sum(rec: dict, key: str, weeks) -> int:
    got = (rec or {}).get(key) or {}
    return round(sum(float(got.get(w) or 0) for w in weeks))


def month_view(store: dict, month: str) -> dict:
    """그 달의 묶음별 계획·실적. 홈 카드 · 매출 상세 · admin 이 같이 쓴다."""
    year = str(month)[:4]
    y = (store.get("years") or {}).get(year) or {}
    weeks = _months_of(y, month)
    totals = y.get("totals") or {}
    lines = y.get("lines") or []

    def box(key, label):
        rec = totals.get(key) or {}
        b = _sum(rec, "budget", weeks)
        p = _sum(rec, "plan", weeks)
        a = _sum(rec, "actual", weeks)
        items = []
        for ln in lines:
            if ln.get("group") != key:
                continue
            la = _sum(ln, "actual", weeks)
            lp = _sum(ln, "plan", weeks)
            lb = _sum(ln, "budget", weeks)
            items.append({"item": ln.get("label") or "", "cust": ln.get("cust") or "",
                          "group": key, "budget": lb, "plan": lp, "actual": la,
                          "rate": round(la * 100 / lp) if lp > 0 else None})
        items.sort(key=lambda r: (-r["actual"], -r["plan"], r["item"]))
        return {"key": key, "label": label, "budget": b, "plan": p, "actual": a,
                "rate": round(a * 100 / p) if p > 0 else None,
                "items": items,
                # 세부를 더한 값. 합계와 다르면 화면에서 말해 준다.
                "items_actual": sum(r["actual"] for r in items)}

    boxes = [box(k, lb) for k, lb in GROUPS]
    internal = box(*INTERNAL)
    sub = totals.get("subtotal") or {}
    grand = totals.get("grand") or {}

    def pack(rec, label, fallback=None):
        b = _sum(rec, "budget", weeks)
        p = _sum(rec, "plan", weeks)
        a = _sum(rec, "actual", weeks)
        if not (b or p or a) and fallback:
            b, p, a = fallback
        return {"label": label, "budget": b, "plan": p, "actual": a,
                "rate": round(a * 100 / p) if p > 0 else None}

    sub_fb = (sum(x["budget"] for x in boxes), sum(x["plan"] for x in boxes),
              sum(x["actual"] for x in boxes))
    subtotal = pack(sub, "소계 (Sub-total)", sub_fb)
    gr_fb = (subtotal["budget"] + internal["budget"],
             subtotal["plan"] + internal["plan"],
             subtotal["actual"] + internal["actual"])
    grand_v = pack(grand, "총합 (내부거래 포함)", gr_fb)

    # 누적은 보고 있는 달까지 (뒤에 오는 달이 들어가면 1~8월 합과 안 맞는다)
    upto = []
    for m, ws in sorted((y.get("months") or {}).items()):
        if m <= month:
            upto.extend(ws)
    ytd = _sum(grand, "actual", upto) or sum(
        _sum(totals.get(k) or {}, "actual", upto) for k in ("semi", "dc", "space", "internal"))

    last = ""
    for w in weeks:
        if _sum(grand or (totals.get("semi") or {}), "actual", [w]) > 0:
            last = w
    return {
        "month": month, "weeks": weeks,
        "groups": boxes, "internal": internal,
        "subtotal": subtotal, "grand": grand_v,
        "plan": grand_v["plan"], "actual": grand_v["actual"],
        "budget": grand_v["budget"], "rate": grand_v["rate"],
        "left": max(0, grand_v["plan"] - grand_v["actual"]),
        "ytd": ytd, "as_of": last,
        "has_data": bool(weeks) and bool(totals),
        "sources": store.get("sources") or {},
    }
