"""하바플레이트 'W35계획' 형태의 주간 현황 엑셀 파서.

한 시트가 한 주차의 스냅샷이다. 시트 이름이 곧 주차(W35).

    1. 현황            그룹별 총모델수 / PO수량 / 변동 / 출하수량 / PO잔량
    2. 양산모델        모델별 판가 / PO 수량 / 출하수량 / PO 잔량
    3~5. 개발품 …      모델별 (+ 개발단계 / 개발종류)
    (마지막 표)        파트번호별 월별 실적 — 위와 중복이라 읽지 않는다

섹션마다 열 위치가 다르므로 머리글 이름으로 찾는다.
"""

import re
import datetime as _dt

# 열 머리글 별칭
_ALIAS = {
    "model": ["모델", "모델명", "파트번호", "파트넘버"],
    "price": ["판가"],
    "po": ["po수량", "poq'ty", "poqty"],
    "ship": ["출하수량", "shipped", "shippedqty", "출하실적"],
    "rem": ["po잔량", "openpo"],
    "devkind": ["개발종류"],
    "stage": ["개발단계"],
    "cnt": ["총모델수", "총모델"],
    "delta": ["변동", "증감", "po증감"],
}


def _s(ws, r, c):
    if c is None or c < 1:
        return ""
    v = ws.cell(r, c).value
    return "" if v is None else str(v).strip()


def _num(v):
    t = str(v if v is not None else "").replace(",", "").strip()
    if t in ("", "-", "N/A", "n/a", "없음"):
        return None
    try:
        return int(round(float(t)))
    except Exception:
        return None


def _key(t):
    return re.sub(r"\s+", "", str(t or "")).lower()


def _map_header(ws, r, want):
    """머리글 행에서 원하는 열들을 이름으로 찾는다."""
    out = {}
    for c in range(1, ws.max_column + 1):
        t = _key(_s(ws, r, c))
        if not t:
            continue
        for k in want:
            if k in out:
                continue
            if any(t == a or t.startswith(a) for a in _ALIAS[k]):
                out[k] = c
    return out


# ────────────────────────────────────────────────────────────────
# 1. 현황
# ────────────────────────────────────────────────────────────────
def parse_status(ws):
    """그룹별 PO / 출하 / 변동 / 진행중·완료 종수."""
    hdr = None
    for r in range(1, min(ws.max_row, 15) + 1):
        line = _key("".join(_s(ws, r, c) for c in range(1, min(ws.max_column, 14) + 1)))
        if "po수량" in line and ("총모델" in line or "출하수량" in line):
            hdr = r
            break
    if hdr is None:
        return None

    cm = _map_header(ws, hdr, ("cnt", "po", "ship", "delta"))
    if "po" not in cm:
        return None

    out = {
        "양산": {"po": 0, "ship": 0, "cnt": 0, "delta": 0},
        "개발": {"po": 0, "ship": 0, "cnt": 0, "delta": 0},
        "ongoing_types": 0,
        "done_types": 0,
    }
    label_end = min(cm.get("cnt", 4), 4)
    cur = None
    for r in range(hdr + 1, hdr + 14):
        label = " ".join(_s(ws, r, c) for c in range(1, label_end)).strip()
        if "합산" in label or "합계" in label:
            break
        if "양산" in label and "개발" not in label and "전환" not in label:
            cur = "양산"
        elif "개발" in label:
            cur = "개발"
        if cur is None:
            continue
        po = _num(_s(ws, r, cm.get("po")))
        sh = _num(_s(ws, r, cm.get("ship")))
        cnt = _num(_s(ws, r, cm.get("cnt")))
        dl = _num(_s(ws, r, cm.get("delta")))
        if po is None and sh is None and cnt is None:
            continue
        out[cur]["po"] += po or 0
        out[cur]["ship"] += sh or 0
        out[cur]["cnt"] += cnt or 0
        out[cur]["delta"] += dl or 0
        if cur == "개발":
            if "진행중" in label:
                out["ongoing_types"] += cnt or 0
            elif "완료" in label:
                out["done_types"] += cnt or 0
    return out


# ────────────────────────────────────────────────────────────────
# 2~5. 모델별 표
# ────────────────────────────────────────────────────────────────
def parse_models(ws):
    """번호가 붙은 섹션('2. 양산모델' …)의 모델 행만 읽는다."""
    # 섹션 제목 행: 'N. ...'
    titles = []
    for r in range(1, ws.max_row + 1):
        head = " ".join(_s(ws, r, c) for c in range(1, 5)).strip()
        m = re.match(r"^\s*(\d+)\s*\.\s*(.+)$", head)
        if m:
            titles.append((r, m.group(2)))

    sections = []
    for ti, (tr, title) in enumerate(titles):
        if "현황" in title:
            continue
        end = titles[ti + 1][0] - 1 if ti + 1 < len(titles) else ws.max_row
        # 제목 아래 3행 안에서 머리글 찾기
        hdr = None
        for r in range(tr, min(tr + 4, end) + 1):
            cm = _map_header(ws, r, ("model", "price", "po", "ship", "devkind", "stage"))
            if "model" in cm and "po" in cm and "ship" in cm:
                hdr, cmap = r, cm
                break
        if hdr is None:
            continue
        group = "양산" if ("양산모델" in _key(title) or _key(title) == "양산") else "개발"
        # 섹션 끝: 다음 제목 전, 또는 새로운 머리글 행 직전.
        # (맨 아래 '파트번호별 월별 실적' 표는 번호 제목이 없어 여기서 잘린다)
        for r in range(hdr + 1, end + 1):
            nx = _map_header(ws, r, ("model", "po", "ship"))
            if "model" in nx and "po" in nx and "ship" in nx:
                end = r - 1
                break
        sections.append((hdr, end, cmap, group))

    rows = []
    for hdr, end, cm, group in sections:
        for r in range(hdr + 1, end + 1):
            mid = _s(ws, r, cm["model"])
            if not mid or _key(mid) in ("total", "합계", "소계", "."):
                continue
            if not re.search(r"\d", mid):
                continue
            # 파트번호가 아닌 요약 행('개발 (45종 진행중 …)') 은 건너뛴다
            if re.search(r"[가-힣]", mid):
                continue
            po = _num(_s(ws, r, cm.get("po")))
            sh = _num(_s(ws, r, cm.get("ship")))
            if po is None and sh is None:
                continue
            rows.append({
                "id": mid,
                "group": group,
                "price": _num(_s(ws, r, cm.get("price"))),
                "po_qty": po or 0,
                "shipped_qty": sh or 0,
                "dev_type": _s(ws, r, cm.get("devkind")).upper(),
                "stage": _s(ws, r, cm.get("stage")),
            })
    # 같은 모델이 여러 섹션에 나오면 뒤엣것으로 덮어쓴다
    dedup = {}
    for x in rows:
        dedup[_key(x["id"])] = x
    return list(dedup.values())


def parse_sheet(ws):
    return {"status": parse_status(ws), "models": parse_models(ws)}


def sheet_week(name):
    m = re.match(r"^\s*W\s*(\d{1,2})\s*$", str(name or ""), re.I)
    return int(m.group(1)) if m else None


def week_monday(week, today=None):
    """주차 번호 → 그 주 월요일 날짜. 연도는 오늘 기준으로 정한다."""
    today = today or _dt.date.today()
    y = today.year
    try:
        cur = today.isocalendar()[1]
    except Exception:
        cur = 1
    if week > cur + 6:
        y -= 1
    try:
        return _dt.date.fromisocalendar(y, week, 1)
    except Exception:
        return today


def parse_workbook(wb):
    """주차 순으로 [(주차, 시트명, 파싱결과)]."""
    out = []
    for name in wb.sheetnames:
        w = sheet_week(name)
        if w is None:
            continue
        try:
            out.append((w, name, parse_sheet(wb[name])))
        except Exception as e:
            print(f"[hrva] {name} 파싱 실패(무시): {e}")
    out.sort(key=lambda x: x[0])
    return out
