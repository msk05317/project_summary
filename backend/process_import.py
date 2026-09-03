"""개발 프로세스 일정표 엑셀 파서 (Process Schedule 형식).

표 구조 (거의 고정):
  1행 : No. | Part Number | 01 FA PO | 02 Material Order | ... | 13 Final Approval Complete | Comment
        (단계 머리글은 두 칸을 병합해서 씀)
  2행 : (빈칸) (빈칸) Planned Actual Planned Actual ...
  3행~: 순번 | 파트넘버 | 날짜들...

날짜가 아닌 값('지속 입고중', '가공전', '확인중', '-')은 완료로 보지 않고
진행중 표시 + 메모로 남긴다.
"""

import re
import datetime as _dt

STEP_HEAD_RE = re.compile(r"^(\d{1,2})\s*[.\-]?\s*(.+)$")
NOT_DONE_TEXT = {"-", "n/a", "na", "tbd", "미정", "확인중", "확인 중"}


def _s(v):
    return "" if v is None else str(v).strip()


def _as_date(v):
    """날짜면 'YYYY-MM-DD', 아니면 None."""
    if isinstance(v, (_dt.datetime, _dt.date)):
        d = v.date() if isinstance(v, _dt.datetime) else v
        return d.isoformat()
    t = _s(v)
    if not t:
        return None
    t2 = t.replace(".", "-").replace("/", "-")
    m = re.match(r"^(\d{2,4})-(\d{1,2})-(\d{1,2})", t2)
    if not m:
        return None
    y, mo, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
    if y < 100:
        y += 2000
    try:
        return _dt.date(y, mo, d).isoformat()
    except Exception:
        return None


def find_layout(ws, max_scan=10):
    """(헤더행, 파트넘버열, [(단계번호, 단계명, 계획열, 실적열)], 코멘트열) 반환."""
    head_row = None
    pn_col = None
    for r in range(1, min(ws.max_row, max_scan) + 1):
        for c in range(1, ws.max_column + 1):
            t = _s(ws.cell(row=r, column=c).value).lower()
            if t in ("part number", "partnumber", "파트넘버", "파트 넘버", "모델", "모델명"):
                head_row, pn_col = r, c
                break
        if head_row:
            break
    if head_row is None:
        return None, None, [], None

    sub_row = head_row + 1
    subs = {c: _s(ws.cell(row=sub_row, column=c).value).lower()
            for c in range(1, ws.max_column + 1)}

    steps = []
    comment_col = None
    for c in range(pn_col + 1, ws.max_column + 1):
        label = _s(ws.cell(row=head_row, column=c).value)
        if not label:
            continue
        if label.lower().startswith("comment") or label in ("비고", "메모"):
            comment_col = c
            continue
        m = STEP_HEAD_RE.match(label)
        if not m:
            continue
        no, name = int(m.group(1)), m.group(2).strip()
        plan_c, act_c = c, c + 1
        if subs.get(c, "").startswith("actual") or subs.get(c, "") in ("실적",):
            plan_c, act_c = c - 1, c
        steps.append((no, name, plan_c, act_c))
    steps.sort(key=lambda x: x[0])
    return head_row, pn_col, steps, comment_col


def parse_process_schedule(wb, sheet_name=None):
    ws = wb[sheet_name] if sheet_name and sheet_name in wb.sheetnames else None
    layout = None
    if ws is not None:
        layout = find_layout(ws)
    else:
        for name in wb.sheetnames:
            cand = wb[name]
            lay = find_layout(cand)
            if lay[0] is not None and len(lay[2]) >= 5:
                ws, layout = cand, lay
                break
    if ws is None or layout is None or layout[0] is None or not layout[2]:
        return {"sheet": None, "steps": [], "rows": []}

    head_row, pn_col, steps, comment_col = layout
    rows = []
    for r in range(head_row + 2, ws.max_row + 1):
        pn = _s(ws.cell(row=r, column=pn_col).value)
        if not pn or pn.lower() in ("total", "합계"):
            continue
        cells = []
        notes = []
        for no, name, pc, ac in steps:
            raw_p = ws.cell(row=r, column=pc).value if pc >= 1 else None
            raw_a = ws.cell(row=r, column=ac).value if ac >= 1 else None
            exp = _as_date(raw_p)
            act = _as_date(raw_a)
            status = ""
            if act:
                status = "완료"
            else:
                for raw in (raw_a, raw_p):
                    t = _s(raw)
                    if t and t.lower() not in NOT_DONE_TEXT and _as_date(raw) is None:
                        status = "진행중"
                        notes.append(f"{no:02d} {name}: {t}")
                        break
            cells.append({
                "no": no,
                "name": name,
                "expected": exp or "",
                "actual": act or "",
                "status": status,
            })
        rows.append({
            "part_number": pn,
            "steps": cells,
            "comment": _s(ws.cell(row=r, column=comment_col).value) if comment_col else "",
            "notes": notes,
        })

    return {
        "sheet": ws.title,
        "steps": [{"no": n, "name": nm} for n, nm, _, _ in steps],
        "rows": rows,
    }
