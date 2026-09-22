"""블룸 '대표님 일 보고 자료' 시트 파서.

시트 모양 (2026-09 ver3 기준)

    A      C          D      E        F           G     H    I    J/K      L~   ...
    CODE   품목       출하   구매품   공정        공정  9월 합계  9/9 이전  날짜별 계획/실적
                      대기   대기                 재고  계획 실적 계획 실적  (계획, 실적) x N

  - 품목 하나가 세로로 병합돼 있고 그 안에 공정 행이 2~3개 붙는다
    (NCT(박닌) / 조립(박장) / 출하). 공정 이름은 시트에 적힌 그대로 쓴다.
  - 날짜 머리글은 주차 밴드(37주차·38주차) 아래 병합돼 있고, 그 아래가 계획/실적이다.
  - 마지막 품목 아래에 ◆ 로 시작하는 자재 입고 메모가 붙는다.

열 위치는 고정하지 않는다. '계획'이 여러 번 나오는 행을 찾아 하위 머리글로 삼고,
그 위에서 날짜를 거슬러 올라가 찾는다. 시트가 옆으로 늘어나도 따라간다.
"""

import datetime as _dt
import re

NOTE_RE = re.compile(r"^\s*[◆◇■□●○*・\-]\s*(.+)$")
ETA_RE = re.compile(r"ETA\s*[:：]?\s*([0-9]{1,2}\s*/\s*[0-9]{1,2})", re.I)


def _s(v):
    return "" if v is None else str(v).strip()


def _num(v):
    """수량 칸. 빈 칸과 0 은 다르다 — 빈 칸은 None(아직 입력 전)."""
    if v is None:
        return None
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        try:
            return int(round(v))
        except Exception:
            return None
    t = str(v).strip().replace(",", "")
    if t in ("", "-", "–", "—", "N/A", "n/a"):
        return None
    try:
        return int(round(float(t)))
    except Exception:
        return None


def _as_date(v):
    if isinstance(v, _dt.datetime):
        return v.date()
    if isinstance(v, _dt.date):
        return v
    t = _s(v)
    if not t:
        return None
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d", "%Y/%m/%d", "%m/%d"):
        try:
            d = _dt.datetime.strptime(t, fmt).date()
            return d.replace(year=_dt.date.today().year) if fmt == "%m/%d" else d
        except ValueError:
            continue
    return None


def step_group(step):
    """'NCT(박닌)' -> 'NCT', '조립(박장)' -> '조립', '출하' -> '출하'.

    화면에는 시트에 적힌 그대로 쓰고, 합계를 낼 때만 이걸 쓴다.
    공장(박닌/박장)이 달라도 같은 공정으로 묶여야 총계가 맞는다.
    """
    t = re.split(r"[(\uff08]", _s(step))[0].strip()
    return t or _s(step)


def _grid(ws):
    """병합 셀의 앵커 값을 범위 전체에 퍼뜨린 값 배열."""
    g = {}
    for r in range(1, ws.max_row + 1):
        for c in range(1, ws.max_column + 1):
            g[(r, c)] = ws.cell(r, c).value
    for rng in ws.merged_cells.ranges:
        mc, mr, xc, xr = rng.bounds
        val = g.get((mr, mc))
        for rr in range(mr, xr + 1):
            for cc in range(mc, xc + 1):
                g[(rr, cc)] = val
    return g


def find_sheet(wb):
    """'일 보고' 시트 찾기. 이름이 바뀌어도 모양으로 찾는다."""
    for name in wb.sheetnames:
        if "일" in name and "보고" in name:
            return wb[name]
    for name in wb.sheetnames:                     # 이름을 못 믿을 때
        ws = wb[name]
        g = _grid(ws)
        for r in range(1, min(ws.max_row, 12) + 1):
            if sum(1 for c in range(1, ws.max_column + 1)
                   if _s(g.get((r, c))) == "계획") >= 4:
                return ws
    return None


def find_layout(ws, g):
    """(하위머리글행, 열지도, 날짜쌍) — 날짜쌍은 [(date, 계획열, 실적열)]."""
    sub = None
    for r in range(1, min(ws.max_row, 16) + 1):
        if sum(1 for c in range(1, ws.max_column + 1)
               if _s(g.get((r, c))) == "계획") >= 4:
            sub = r
            break
    if sub is None:
        return None

    # 머리글 텍스트로 고정 열을 찾는다 (병합 중복은 걷어낸다)
    cols, pairs = {}, []
    for c in range(1, ws.max_column + 1):
        uniq = []
        # sub-2 까지만 본다. 더 올라가면 C1:I2 에 걸친 제목
        # ('블룸 계획 대비 실적 보고(9/14)')이 C~I 모든 열 머리글에 섞여 들어와
        # '품목' 도 '공정' 도 못 찾는다.
        for r in range(max(1, sub - 2), sub + 1):
            t = _s(g.get((r, c)))
            if t and t not in uniq:
                uniq.append(t)
        flat = "".join(uniq).replace("\n", "").replace(" ", "")
        if flat == "CODE" and "code" not in cols:
            cols["code"] = c
        elif flat in ("품목", "제품명", "품명") and "item" not in cols:
            cols["item"] = c
        elif flat.startswith("재고출하대기") or flat == "출하대기":
            cols.setdefault("wait_ship", c)
        elif "구매품대기" in flat:
            cols.setdefault("wait_part", c)
        elif flat in ("공정", "공정명") and "step" not in cols:
            cols["step"] = c
        elif "공정재고" in flat:
            cols.setdefault("wip", c)
        elif flat == "비고":
            cols.setdefault("note", c)

    # 계획/실적 쌍 → 날짜 또는 누적 칸
    c = 1
    while c <= ws.max_column:
        if _s(g.get((sub, c))) != "계획":
            c += 1
            continue
        act = c + 1 if _s(g.get((sub, c + 1))) == "실적" else None
        day, band = None, ""
        for r in range(sub - 1, 0, -1):
            v = g.get((r, c))
            d = _as_date(v)
            if d and day is None:
                day = d
            t = _s(v)
            if t and not d:
                band = band or t
        if day:
            pairs.append((day, c, act))
        elif "합계" in band or "월" in band:
            cols.setdefault("total_plan", c)
            if act:
                cols.setdefault("total_actual", act)
        elif band:
            cols.setdefault("prior_plan", c)
            cols.setdefault("prior_label", band)
            if act:
                cols.setdefault("prior_actual", act)
        c = (act or c) + 1

    if "item" not in cols or not pairs:
        return None
    return sub, cols, pairs


def parse_daily(wb, sheet_name=None):
    """{'sheet','title','report_date','dates','items':[...],'notes':[...]}

    items = [{'item','code','wait_ship','wait_part','steps':[
                {'step','wip','month_plan','month_actual','prior_plan',
                 'prior_actual','note','days':{'YYYY-MM-DD':{'plan','actual'}}}]}]
    """
    ws = wb[sheet_name] if sheet_name and sheet_name in wb.sheetnames else find_sheet(wb)
    if ws is None:
        return {"sheet": None, "items": [], "dates": [], "notes": []}
    g = _grid(ws)
    lay = find_layout(ws, g)
    if not lay:
        return {"sheet": ws.title, "items": [], "dates": [], "notes": []}
    sub, cols, pairs = lay

    title = ""
    for r in range(1, sub):
        for c in range(1, min(ws.max_column, 12) + 1):
            t = _s(g.get((r, c)))
            if len(t) > 6 and ("보고" in t or "블룸" in t or "BLOOM" in t.upper()):
                title = t
                break
        if title:
            break

    items, order, notes = {}, [], []
    for r in range(sub + 1, ws.max_row + 1):
        name = _s(g.get((r, cols["item"]))).replace("\n", " ").strip()
        name = re.sub(r"\s+", " ", name)
        step = _s(g.get((r, cols["step"]))).replace("\n", " ").strip() if cols.get("step") else ""

        if not name or not step:
            for c in range(1, min(ws.max_column, 12) + 1):
                m = NOTE_RE.match(_s(ws.cell(r, c).value))
                if m and len(m.group(1)) > 3:
                    txt = re.sub(r"\s+", " ", m.group(1)).strip()
                    eta = ETA_RE.search(txt)
                    notes.append({"text": txt,
                                  "eta": eta.group(1).replace(" ", "") if eta else ""})
                    break
            continue

        if name not in items:
            items[name] = {
                "item": name,
                "code": _s(g.get((r, cols["code"]))).replace("\n", " ").strip()
                        if cols.get("code") else "",
                "wait_ship": _num(g.get((r, cols["wait_ship"]))) if cols.get("wait_ship") else None,
                "wait_part": _num(g.get((r, cols["wait_part"]))) if cols.get("wait_part") else None,
                "steps": [],
            }
            order.append(name)

        days = {}
        for day, pc, ac in pairs:
            p = _num(ws.cell(r, pc).value)
            a = _num(ws.cell(r, ac).value) if ac else None
            if p is None and a is None:
                continue
            days[day.strftime("%Y-%m-%d")] = {"plan": p, "actual": a}

        items[name]["steps"].append({
            "step": step,
            "group": step_group(step),
            "wip": _num(ws.cell(r, cols["wip"]).value) if cols.get("wip") else None,
            "month_plan": _num(ws.cell(r, cols["total_plan"]).value) if cols.get("total_plan") else None,
            "month_actual": _num(ws.cell(r, cols["total_actual"]).value) if cols.get("total_actual") else None,
            "prior_plan": _num(ws.cell(r, cols["prior_plan"]).value) if cols.get("prior_plan") else None,
            "prior_actual": _num(ws.cell(r, cols["prior_actual"]).value) if cols.get("prior_actual") else None,
            "note": _s(ws.cell(r, cols["note"]).value) if cols.get("note") else "",
            "days": days,
        })

    dates = sorted({d.strftime("%Y-%m-%d") for d, _, _ in pairs})
    # 보고 기준일: 제목의 (9/14) 우선, 없으면 실적이 적힌 마지막 날 다음 날
    report = ""
    m = re.search(r"\((\d{1,2})\s*/\s*(\d{1,2})\)", title)
    if m and dates:
        y = int(dates[0][:4])
        try:
            report = _dt.date(y, int(m.group(1)), int(m.group(2))).strftime("%Y-%m-%d")
        except ValueError:
            report = ""

    return {
        "sheet": ws.title,
        "title": title,
        "report_date": report,
        "prior_label": cols.get("prior_label", ""),
        "dates": dates,
        "items": [items[n] for n in order],
        "notes": notes,
    }


# ── '금액 실적' 시트 ─────────────────────────────────────────────────
#
#   제품명 | CODE | 출하 국가 | 단가 USD | 영업 계획          | 예상실적
#                                       | 09월 출하계획 | 09월 매출계획 USD | 09월 출하계획 | 09월 매출계획 USD | 09월 출하 완료 | 09월 매출완료 USD | 잔량
#
# '출하계획' · '매출계획' 이 두 번 나온다 (영업 계획 / 예상실적). 계획으로는
# 뒤의 예상실적을 쓴다 — 시트의 '달성율' 도 그걸 분모로 쓴다.
# 앞의 영업 계획은 sales_* 로 따로 둔다.

def _norm(t):
    return re.sub(r"\s+", "", _s(t)).lower()


def find_money_sheet(wb):
    for ws in wb.worksheets:
        g = _grid(ws)
        for r in range(1, min(ws.max_row, 12) + 1):
            row = [_norm(g.get((r, c))) for c in range(1, ws.max_column + 1)]
            if any("매출완료" in t for t in row) and any("매출계획" in t for t in row):
                return ws, g, r
    return None, None, None


def parse_money(wb):
    """{'sheet','month','items':[...],'total':{...},'stated_rate'} 또는 None."""
    ws, g, hr = find_money_sheet(wb)
    if ws is None:
        return None
    row = {c: _norm(g.get((hr, c))) for c in range(1, ws.max_column + 1)}
    up = {c: _norm(g.get((hr - 1, c))) for c in range(1, ws.max_column + 1)} if hr > 1 else {}

    def cols(pred):
        return [c for c, t in row.items() if t and pred(t)]

    plan_q = cols(lambda t: "출하계획" in t)
    plan_u = cols(lambda t: "매출계획" in t)
    done_q = cols(lambda t: "출하" in t and "완료" in t and "매출" not in t)
    done_u = cols(lambda t: "매출완료" in t)
    if not plan_u or not done_u:
        return None
    # 제품명 · 국가 · 단가는 윗줄 머리글에 있다
    def find_up(*keys):
        for c in range(1, ws.max_column + 1):
            t = up.get(c, "") or row.get(c, "")
            if any(k in t for k in keys):
                return c
        return None
    c_name = find_up("제품명", "품목", "item")
    c_cty = find_up("국가")
    c_price = find_up("단가")
    if not c_name:
        return None

    month = ""
    m = re.search(r"(\d{1,2})\s*월", _s(g.get((hr, plan_u[-1]))))
    if m:
        month = str(int(m.group(1)))

    def num(r, c):
        if not c:
            return None
        v = ws.cell(r, c).value
        if isinstance(v, (int, float)) and not isinstance(v, bool):
            return float(v)
        try:
            return float(str(v).replace(",", "").replace("$", "").strip())
        except Exception:
            return None

    items, total = [], None
    for r in range(hr + 1, ws.max_row + 1):
        name = re.sub(r"\s+", " ", _s(g.get((r, c_name)))).strip()
        if not name:
            continue
        rec = {
            "item": name,
            "country": _s(ws.cell(r, c_cty).value) if c_cty else "",
            "price": num(r, c_price),
            "sales_qty": num(r, plan_q[0]) if len(plan_q) > 1 else None,
            "sales_usd": num(r, plan_u[0]) if len(plan_u) > 1 else None,
            "plan_qty": num(r, plan_q[-1]) if plan_q else None,
            "plan_usd": num(r, plan_u[-1]),
            "done_qty": num(r, done_q[0]) if done_q else None,
            "done_usd": num(r, done_u[0]),
        }
        if name.replace(" ", "") in ("합계", "총계", "total", "TOTAL"):
            total = rec
            break
        if rec["plan_usd"] is None and rec["done_usd"] is None:
            continue
        items.append(rec)
    if not items:
        return None

    def s(f):
        return round(sum(x.get(f) or 0 for x in items), 2)
    calc = {f: s(f) for f in ("sales_qty", "sales_usd", "plan_qty", "plan_usd", "done_qty", "done_usd")}
    return {
        "sheet": ws.title,
        "month": month,
        "items": items,
        # 시트의 합계 줄보다 우리가 더한 값을 쓴다. 합계 줄이 손으로 고쳐져 있기도 하다.
        "total": calc,
        "stated_total": total,
    }
