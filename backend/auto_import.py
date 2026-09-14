"""자동차사업부 '양산주요제품' 엑셀 파서.

한 제품이 두 줄이다. 위가 비용, 아래가 비율(%)이다. 연도별 값도 두 줄에 나뉜다.
위가 물량, 아래가 매출(억원)이다. 고객사는 여러 줄에 걸쳐 병합돼 있다.

    고객사 제품명 ... 재료비 부품비 주조비 ... 판가 | 현재단계 SOP | 총 2026 2027 ...
    셰플러 SVCT   ... 23488  1200  10768 ... 36531 | 양산   2024.4 | 물량 729100 116755 ...
                  ... 46.4%  2.3%  21.3% ...       |               | 매출 354.3  56.7   ...

원가는 다섯 덩어리로 묶는다. 화면이 그렇게 보여주고, 엑셀 여덟 칸은 이렇게 접힌다.
    재료비 = 재료비 + 부품비 + 포장
    공정비 = 주조비 + 가공비
    관리이윤 · 감가상각 · 물류 는 그대로
(SVCT 23,488+1,200+1,142 = 25,830 / 10,768+6,347 = 17,115. 발레오도 7,510 / 6,663.)

판가는 '=27.06*1350' 처럼 외화 단가 × 환율로 들어 있다. 값만 읽으면 그 둘을
잃어버리므로 수식도 같이 본다. 1650 이면 EUR, 아니면 USD 로 본다 (발레오=프랑스).

비율(%) 행과 합계·공정비 열은 읽지 않는다. 원본에서 계산된 값이라
어긋나 있을 수 있고, 화면이 어차피 다시 계산한다.
"""

from __future__ import annotations

import re

# 엑셀 머리글 → 우리 이름
HEAD = {
    "고객사": "customer", "제품명": "product", "모델명": "model_name",
    "최종고객사": "end_customer", "차종": "car_model", "납품위치": "site",
    "제품중량": "weight_kg", "주조톤수": "tonnage", "구분": "kind",
    "재료비": "c_material", "부품비": "c_parts", "주조비": "c_casting",
    "가공비": "c_machining", "관리이윤": "c_margin", "감가상각": "c_depr",
    "포장": "c_packing", "물류": "c_logi",
    # 시트마다 원가를 쪼갠 정도가 다르다. 주조비·가공비로 나뉜 시트가 있고
    # 공정비 한 칸으로만 있는 시트가 있다. 둘 다 읽는다.
    "공정비": "c_process",
    # 엑셀이 스스로 낸 합계. 우리가 모은 다섯 덩어리와 맞는지 대조용으로만 쓴다.
    "합계": "c_total",
    "판가": "price", "불량률": "defect_rate",
    "현재단계": "stage", "SOP시점": "sop",
}
YEAR_RE = re.compile(r"^(20\d{2})$")
PRICE_FX_RE = re.compile(r"^=\s*([\d.]+)\s*\*\s*([\d.]+)\s*$")
STOP = ("총매출", "합계", "총계")


def _s(v):
    return "" if v is None else " ".join(str(v).split())


def _key(v):
    return re.sub(r"[\s()\n]", "", _s(v))


def _num(v):
    if v is None or v == "":
        return None
    if isinstance(v, str):
        v = v.replace(",", "").replace("%", "").strip()
        if not v or v.startswith("="):
            return None
    try:
        return float(v)
    except Exception:
        return None


def _merged_value(ws, r, c):
    """병합 셀이면 왼쪽 위 값을 돌려준다 (고객사처럼 세로 병합된 칸)."""
    v = ws.cell(r, c).value
    if v is not None:
        return v
    for rng in ws.merged_cells.ranges:
        if rng.min_row <= r <= rng.max_row and rng.min_col <= c <= rng.max_col:
            return ws.cell(rng.min_row, rng.min_col).value
    return None


def _find_header(ws, max_scan=12):
    """'고객사' 와 '제품명' 이 같이 있는 행 → (행번호, {이름: 열}, {연도: 열})"""
    for r in range(1, min(ws.max_row, max_scan) + 1):
        cols, years = {}, {}
        for c in range(1, ws.max_column + 1):
            k = _key(ws.cell(r, c).value)
            if not k:
                continue
            m = YEAR_RE.match(k)
            if m:
                years[m.group(1)] = c
                continue
            hit = HEAD.get(k)
            if hit is None:
                # 긴 이름부터 본다 ('제품중량' 이 '제품명' 에 먹히지 않게)
                for hk in sorted(HEAD, key=len, reverse=True):
                    if k.startswith(hk):
                        hit = HEAD[hk]
                        break
            if hit:
                cols.setdefault(hit, c)
        if "customer" in cols and "product" in cols:
            return r, cols, years
    return None


def parse(wb, wb_formula=None, sheet=None):
    """워크북 → {'sheet', 'years', 'rows'[]}. 못 읽으면 None.

    wb          값 워크북 (data_only=True). 숫자는 여기서 읽는다.
    wb_formula  수식 워크북. 판가의 '외화 단가 × 환율' 을 살리는 데만 쓴다.
                값 워크북만 주면 판가는 원화 한 덩어리로 들어간다.
    """
    names = [sheet] if sheet else list(wb.sheetnames)
    for nm in names:
        if nm not in wb.sheetnames:
            continue
        ws = wb[nm]
        hdr = _find_header(ws)
        if not hdr:
            continue
        wsf = wb_formula[nm] if (wb_formula and nm in wb_formula.sheetnames) else None
        got = _read_sheet(ws, hdr, wsf)
        if got and got["rows"]:
            return got
    return None


def _read_sheet(ws, hdr, wsf=None):
    head_row, cols, years = hdr
    ylist = sorted(years)
    rows = []
    r = head_row + 1
    customer = ""
    while r <= ws.max_row:
        cust = _s(_merged_value(ws, r, cols["customer"])) or customer
        product = _s(_merged_value(ws, r, cols["product"]))
        if _key(cust) in STOP or _key(product) in STOP:
            break
        if not product:
            r += 1
            continue
        customer = cust

        def cell(name, row=r):
            c = cols.get(name)
            return _merged_value(ws, row, c) if c else None

        # 원가 칸들 → 다섯 덩어리
        g = lambda k: _num(cell(k)) or 0.0          # noqa: E731
        # 공정비는 시트에 따라 주조비+가공비로 나뉘어 있거나 한 칸으로만 있다.
        # 나뉜 칸이 있으면 그걸 쓰고, 없을 때만 공정비 칸을 쓴다.
        # (나뉜 시트의 '공정비' 칸은 포장·물류까지 섞인 다른 합이라 같이 더하면 겹친다)
        process = g("c_casting") + g("c_machining") or g("c_process")
        cost = {
            "material": g("c_material") + g("c_parts") + g("c_packing"),
            "process": process,
            "admin": g("c_margin"),
            "depr": g("c_depr"),
            "logi": g("c_logi"),
        }
        cost = {k: v for k, v in cost.items() if v}

        # 엑셀이 적어 둔 합계와 맞는지 본다. 열 구성이 시트마다 달라서
        # 한 칸을 놓쳐도 숫자는 그럴듯하게 나온다 — 그때 잡히는 건 이 대조뿐이다.
        excel_total = _num(cell("c_total"))
        total_gap = None
        if excel_total:
            gap = sum(cost.values()) - excel_total
            if abs(gap) > max(1.0, excel_total * 0.005):
                total_gap = round(gap, 1)

        # 판가 — 수식이면 외화 단가와 환율을 살린다
        price_fx = fx_rate = price_krw = None
        c_price = cols.get("price")
        if c_price:
            m = None
            if wsf is not None:
                f = wsf.cell(r, c_price).value       # '=27.06*1350'
                m = PRICE_FX_RE.match(_s(f)) if isinstance(f, str) else None
            if m:
                price_fx, fx_rate = float(m.group(1)), float(m.group(2))
            else:
                price_krw = _num(_merged_value(ws, r, c_price))

        # 연도별: 이 줄이 물량, 다음 줄이 매출
        contract = {}
        for y in ylist:
            q = _num(_merged_value(ws, r, years[y]))
            v = _num(_merged_value(ws, r + 1, years[y]))
            if q or v:
                contract[y] = {}
                if q:
                    contract[y]["qty"] = int(round(q))
                if v:
                    contract[y]["revenue"] = v

        stage = _s(cell("stage"))
        rows.append({
            "row": r,
            "customer": cust,
            "product": product,
            "group": "개발" if "개발" in stage else "양산",
            "total_gap": total_gap,
            "auto": _clean({
                "model_name": _s(cell("model_name")),
                "end_customer": _s(cell("end_customer")),
                "car_model": _s(cell("car_model")),
                "site": _s(cell("site")),
                "sop": _s(cell("sop")),
                "weight_kg": _num(cell("weight_kg")),
                "tonnage": _num(cell("tonnage")),
                "defect_rate": _num(cell("defect_rate")),
                # 통화는 엑셀에 없다. 환율만 보고 EUR/USD 를 찍던 걸 뺀다 —
                # 맞을 수도 있지만 근거가 없으면 적지 않는 게 낫다.
                "price_fx": price_fx,
                "fx_rate": fx_rate,
                "price_krw": price_krw,
                "cost": cost,
                "contract": contract,
            }),
        })
        r += 2          # 비용 행 + 비율 행

    return {"sheet": ws.title, "years": ylist, "rows": rows}


def _clean(d):
    return {k: v for k, v in d.items() if v not in (None, "", {}, [])}


def sheets(wb, wb_formula=None):
    """어느 시트가 읽히는지만 훑는다 (같은 표의 개정본이 여러 장 있다)."""
    out = []
    for nm in wb.sheetnames:
        try:
            hdr = _find_header(wb[nm])
            if not hdr:
                continue
            wsf = wb_formula[nm] if (wb_formula and nm in wb_formula.sheetnames) else None
            got = _read_sheet(wb[nm], hdr, wsf)
        except Exception:
            continue
        if got and got["rows"]:
            out.append({"sheet": nm, "rows": len(got["rows"]), "years": got["years"]})
    return out


def name_labels(projects):
    """별칭 → 등록된 표기. 엑셀에 '스탈란티스' 로 적혀 있어도 화면에는
    등록된 '스텔란티스' 로 나가게 하려고 쓴다."""
    out = {}
    for p in projects:
        lab = _s(p.get("label"))
        if not lab:
            continue
        for nm in [lab] + list(p.get("aliases") or []):
            k = _key(nm).lower()
            if k:
                out.setdefault(k, lab)
    return out


def canonical(name, labels):
    """등록된 고객사 이름이면 등록 표기로 바꾼다.

    모르는 이름은 손대지 않는다. 최종고객사 칸에는 기아자동차·현대자동차·CEER·PSA
    처럼 프로젝트가 아닌 회사도 들어온다.
    """
    return labels.get(_key(name).lower(), _s(name))


def match_projects(rows, projects):
    """고객사 이름 → 프로젝트 키.

    라벨과 별칭을 공백·대소문자만 지워서 맞춘다. 비슷한 이름 추측은 하지 않는다.
    '고압주조' 와 '저압주조' 도 한 글자 차이라, 닮았다고 이어 붙이면 엉뚱한
    고객사 밑으로 제품이 들어간다. 못 찾은 고객사는 미리보기에서 그대로 보여주고
    (엑셀 '스탈란티스' ↔ 등록 '스텔란티스' 처럼) 별칭으로 명시해 해결한다.

    projects: [{'id','label','aliases':[...]}]
    """
    idx = {}
    for p in projects:
        for nm in [p.get("label")] + list(p.get("aliases") or []):
            k = _key(nm).lower()
            if k:
                idx.setdefault(k, p["id"])
    return {c: idx.get(_key(c).lower()) for c in {r["customer"] for r in rows}}
