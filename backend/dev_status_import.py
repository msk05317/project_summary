# 개발현황 엑셀 (하바플레이트 '260919_하바플레이트 개발현황.xlsx').
#
# 모델 등록 양식과 열 이름이 겹쳐서(둘 다 '모델', '판가', '비고') 기존 파서가
# 그냥 읽어버리면 두 가지가 어긋난다.
#   1. 'PO 수량' 과 'PO 잔량' 이 둘 다 po 로 시작해서 잔량이 PO 수량 자리를 덮는다
#   2. '구분' 열이 없어서 개발품인데 양산으로 들어간다
# 그래서 이 모양을 먼저 알아보고 따로 읽는다.
#
# 열 구성 (헤더 행은 보통 2행):
#   No | 모델 | 소재 | 판가 | 개발종류 | 연간수량 | PO 수량 | 출하수량 |
#   PO 잔량 | 고객요청일 | 가공 완료 | 비고
#
# '가공 완료' 는 개발 공정의 '가공 (조립)' 단계 계획일이다.
# '고객요청일' 에 'PO 취소' 라고 적히면 그 모델은 드롭예정이다.
import datetime as _dt
import re

# 헤더 이름 → 우리가 쓰는 이름. 공백·점을 지우고 소문자로 맞춰 비교한다.
_ALIAS = {
    "name":      ("모델", "모델명", "파트넘버", "파트번호"),
    "material":  ("소재",),
    "price":     ("판가", "판가($)", "단가"),
    "dev_type":  ("개발종류", "개발유형"),
    "year_qty":  ("연간수량",),
    "po_qty":    ("po수량", "po q'ty", "poqty"),
    "shipped":   ("출하수량", "출하실적", "실적수량"),
    "remaining": ("po잔량", "openpo"),
    "request":   ("고객요청일", "고객요청"),
    "machining": ("가공완료", "가공완료일"),
    "note":      ("비고",),
}

# 날짜가 아니라 말이 적히는 칸들. 그대로 두면 날짜 파싱이 터진다.
_CANCEL_WORDS = ("po 취소", "po취소", "취소", "cancel")
_PENDING_WORDS = ("확인 중", "확인중", "미정", "tbd", "-")


def _norm(v) -> str:
    return re.sub(r"[\s.　]", "", str(v or "")).lower()


def _find_header(ws, limit: int = 12):
    """헤더 행과 열 위치. 못 찾으면 (None, {})."""
    for r in range(1, min(ws.max_row, limit) + 1):
        cols = {}
        for c in range(1, ws.max_column + 1):
            k = _norm(ws.cell(row=r, column=c).value)
            if not k:
                continue
            for field, names in _ALIAS.items():
                if field in cols:
                    continue
                if any(k == _norm(n) for n in names):
                    cols[field] = c
                    break
        # 이 파일이라고 말할 수 있는 최소 조건.
        # '모델 + 개발종류' 는 모델 등록 양식에는 없는 짝이다.
        if "name" in cols and "dev_type" in cols and (
                "machining" in cols or "request" in cols):
            return r, cols
    return None, {}


def sniff(wb) -> bool:
    """개발현황 엑셀인가."""
    for ws in wb.worksheets:
        r, _ = _find_header(ws)
        if r:
            return True
    return False


def _date(v):
    """셀 값 → 'YYYY-MM-DD' 또는 ''. 날짜가 아니면 ''."""
    if v is None:
        return ""
    if isinstance(v, (_dt.datetime, _dt.date)):
        d = v.date() if isinstance(v, _dt.datetime) else v
        return d.strftime("%Y-%m-%d")
    t = str(v).strip()
    if not t:
        return ""
    m = re.match(r"^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})", t)
    if m:
        try:
            return _dt.date(int(m.group(1)), int(m.group(2)), int(m.group(3))).strftime("%Y-%m-%d")
        except ValueError:
            return ""
    return ""


def _num(v):
    """숫자 칸. 'N/A' 같은 글자는 None."""
    if v is None:
        return None
    if isinstance(v, (int, float)):
        return float(v)
    t = str(v).replace(",", "").replace("$", "").strip()
    if not t:
        return None
    try:
        return float(t)
    except ValueError:
        return None


def parse_sheet(ws):
    r0, cols = _find_header(ws)
    if not r0:
        return []
    out = []
    for r in range(r0 + 1, ws.max_row + 1):
        name = str(ws.cell(row=r, column=cols["name"]).value or "").strip()
        if not name:
            continue
        # 마지막 합계 줄은 모델이 아니다
        if _norm(name) in ("total", "합계", "소계"):
            continue

        def cell(f):
            c = cols.get(f)
            return ws.cell(row=r, column=c).value if c else None

        req_raw = str(cell("request") or "").strip()
        mac_raw = str(cell("machining") or "").strip()
        req_d, mac_d = _date(cell("request")), _date(cell("machining"))
        # 날짜로 읽힌 칸은 말이 아니다. '2026-09-26' 의 '-' 를 '미정' 으로
        # 세면 멀쩡한 줄이 전부 '확인 중' 이 된다.
        low = " ".join(t for t, d in ((req_raw, req_d), (mac_raw, mac_d)) if not d).lower()

        row = {
            "name": name,
            "material": str(cell("material") or "").strip(),
            "price": _num(cell("price")),
            "dev_type": str(cell("dev_type") or "").strip().upper(),
            "po_qty": _num(cell("po_qty")),
            "shipped_qty": _num(cell("shipped")),
            "request_date": req_d,
            "machining_date": mac_d,
            "note": str(cell("note") or "").strip(),
            # 날짜가 아닌 말이 적힌 경우 그대로 남긴다 ('확인 중', 'PO 취소')
            "request_text": "" if req_d else req_raw,
            "machining_text": "" if mac_d else mac_raw,
            "cancelled": any(w in low for w in _CANCEL_WORDS),
            "pending": any(w in low for w in _PENDING_WORDS),
            "row": r,
        }
        out.append(row)
    return out


def parse_workbook(wb):
    """{'sheet': 이름, 'rows': [...]}. 못 읽으면 None."""
    for ws in wb.worksheets:
        rows = parse_sheet(ws)
        if rows:
            return {"sheet": ws.title, "rows": rows}
    return None
