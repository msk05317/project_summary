"""자주 묻는 질문을 데이터에서 바로 답하는 라우터.

LLM 을 거치지 않고 models.json 만으로 확정 답변을 만든다.
매칭되지 않으면 None 을 돌려주고, 기존 LLM 경로가 이어서 처리한다.

다루는 질문
  1) 프로젝트 요약        "하바플레이트", "챔버 현황", "파워박스 어때"
  2) 모델 상태            "713-312133-006", "C08288 진행률", "저 모델 어디까지 왔어"
  3) 이슈/지연            "이슈 있어?", "지연된 거", "문제 있는 모델"
  4) 모델 수/목록         "개발 몇 종", "양산 모델 리스트"
  5) 진행률 랭킹          "진행률 낮은 모델", "제일 빠른 모델"
  6) 공정 단계 조회        "LAIR 승인 남은 모델", "FAIR 제출한 모델"
  7) 데이터 범위          "어떤 주차 있어", "언제까지 등록됐어"
  8) 프로젝트 목록        "프로젝트 뭐 있어"
"""

import re

MODEL_ID_RE = re.compile(r"\b\d{2,3}-[A-Za-z0-9]{5,6}-\d{2,3}\b")
MODEL_TAIL_RE = re.compile(r"\b[A-Za-z]?\d{4,6}-\d{2,3}\b")

DEV_STEP_NAMES = {
    "fa_po": "FA PO", "material_order": "자재 발주", "incoming": "입고",
    "machining": "가공 (조립)", "la_incoming": "LA 입고", "lair_write": "LAIR 제출",
    "lair_approval": "LAIR 승인", "source_inspection": "Source Inspection",
    "fair_write": "FAIR 제출", "fair_approval": "FAIR 승인", "lap_test": "LAP TEST",
    "cdr": "CDR", "final_approval": "최종 승인 완료",
}

DEV_STEP_ALIASES = [
    ("fa_po", ["fa po", "fapo", "발주"]),
    ("material_order", ["자재 발주", "자재발주"]),
    ("incoming", ["입고"]),
    ("machining", ["가공", "조립"]),
    ("la_incoming", ["la 입고", "la입고"]),
    ("lair_write", ["lair 제출", "lair제출", "lair 작성"]),
    ("lair_approval", ["lair 승인", "lair승인"]),
    ("source_inspection", ["source inspection", "소스 검사", "소스검사"]),
    ("fair_write", ["fair 제출", "fair제출", "fair 작성"]),
    ("fair_approval", ["fair 승인", "fair승인"]),
    ("lap_test", ["lap test", "랩테스트", "lap"]),
    ("cdr", ["cdr"]),
    ("final_approval", ["최종 승인", "최종승인"]),
]


def _s(v):
    return "" if v is None else str(v).strip()


def _josa(word, pair=("은", "는")):
    """받침 유무 따라 은/는, 이/가 등을 붙인다."""
    w = _s(word)
    if not w:
        return pair[1]
    ch = w[-1]
    if "가" <= ch <= "힣":
        return pair[0] if (ord(ch) - 0xAC00) % 28 else pair[1]
    return pair[0] if ch.isdigit() or ch.isalpha() else pair[1]


def _filled(proc):
    if not isinstance(proc, list):
        return 0
    return sum(1 for st in proc
               if any(_s((st or {}).get(k)) for k in ("expected", "actual", "status")))


def _model_progress(m, process_progress):
    """모델 진행률. 데이터 없으면 None."""
    if m.get("group") == "개발":
        proc = m.get("process") if isinstance(m.get("process"), list) else []
        if not _filled(proc):
            return None
        return process_progress(proc)
    po = int(m.get("po_qty") or 0)
    if po <= 0:
        return None
    return round(int(m.get("shipped_qty") or 0) * 100 / po)


def _fmt_models(ids, limit=8):
    ids = list(ids)
    if not ids:
        return "없음"
    head = ", ".join(ids[:limit])
    return head + (f" 외 {len(ids) - limit}종" if len(ids) > limit else "")


def resolve(text, project_key, ctx):
    """확정 답변 문자열을 만들거나 None. ctx = {load_models, process_progress,
    process_current, known_weeks, project_label, projects}"""
    t = _s(text)
    if not t:
        return None
    low = t.lower()

    load_models = ctx["load_models"]
    process_progress = ctx["process_progress"]
    process_current = ctx["process_current"]

    data = load_models()
    projects = data.get("projects") or {}
    proj = projects.get(project_key) if project_key and project_key != "all" else None
    label = ctx.get("project_label") or "이 프로젝트"

    # ── 8) 프로젝트 목록 ──
    if any(k in t for k in ["프로젝트 뭐", "프로젝트 목록", "무슨 프로젝트", "어떤 프로젝트", "프로젝트 리스트"]):
        names = ctx.get("project_labels") or list(projects.keys())
        return f"등록된 프로젝트는 {len(names)}개입니다.\n" + ", ".join(names)

    # ── 7) 데이터 범위 ──
    if any(k in t for k in ["어떤 주차", "무슨 주차", "주차 목록", "몇 주차까지", "언제까지 등록", "데이터 범위"]):
        weeks = sorted(ctx["known_weeks"](project_key),
                       key=lambda w: int(re.sub(r"\D", "", w) or 0))
        if not weeks:
            return "아직 등록된 주차 데이터가 없습니다."
        return f"{label} 등록된 주차는 {weeks[0]}~{weeks[-1]} ({len(weeks)}주)입니다.\n" + ", ".join(weeks)

    if not proj:
        return None

    models = [m for m in (proj.get("models") or []) if isinstance(m, dict)]
    mass = [m for m in models if m.get("group") != "개발"]
    dev = [m for m in models if m.get("group") == "개발"]

    # ── 2) 특정 모델 ──
    mid = None
    hit = MODEL_ID_RE.search(t) or MODEL_TAIL_RE.search(t)
    if hit:
        cand = hit.group(0).lower()
        mid = next((m for m in models if cand in _s(m.get("id")).lower()), None)
    if mid is None:
        # 끝자리만 말한 경우: "C08288", "312133"
        token = re.search(r"[A-Za-z]?\d{4,6}", t)
        if token:
            tk = token.group(0).lower()
            matches = [m for m in models if tk in _s(m.get("id")).lower()]
            if len(matches) == 1:
                mid = matches[0]
    if mid is not None:
        return _answer_model(mid, process_progress, process_current)

    # ── 3) 이슈 / 지연 ──
    if any(k in t for k in ["이슈", "리스크", "문제", "지연", "늦어", "밀린"]):
        rows = []
        for m in models:
            note = _s(m.get("issues"))
            if note:
                rows.append(f"· {m.get('id')}: {note.splitlines()[0][:60]}")
        if not rows:
            return f"{label}에 등록된 이슈가 없습니다."
        return f"{label} 이슈 {len(rows)}건입니다.\n" + "\n".join(rows[:10])

    # ── 6) 공정 단계 조회 (개발) ──
    for key, aliases in DEV_STEP_ALIASES:
        if not any(a in low for a in aliases):
            continue
        if not any(k in t for k in ["남은", "안 된", "안된", "미완", "완료", "끝난", "한 모델", "된 모델", "누구"]):
            break
        done_ids, todo_ids = [], []
        for m in dev:
            proc = m.get("process") if isinstance(m.get("process"), list) else []
            if not _filled(proc):
                continue
            st = next((x for x in proc if x.get("key") == key), None)
            if not st:
                continue
            is_done = bool(_s(st.get("actual"))) or _s(st.get("status")) == "완료"
            (done_ids if is_done else todo_ids).append(_s(m.get("id")))
        name = DEV_STEP_NAMES.get(key, key)
        if any(k in t for k in ["완료", "끝난", "된 모델", "한 모델"]):
            return (f"{label} '{name}' 완료 {len(done_ids)}종입니다.\n{_fmt_models(done_ids)}")
        return (f"{label} '{name}' 미완료 {len(todo_ids)}종입니다.\n{_fmt_models(todo_ids)}")

    # ── 5) 진행률 랭킹 ──
    if any(k in t for k in ["진행률 낮", "제일 늦", "가장 늦", "느린", "뒤처", "진행률 높", "제일 빠", "가장 빠"]):
        scored = []
        for m in models:
            p = _model_progress(m, process_progress)
            if p is not None:
                scored.append((p, _s(m.get("id"))))
        if not scored:
            return f"{label}{_josa(label)} 아직 진행률을 낼 데이터가 없습니다."
        asc = any(k in t for k in ["낮", "늦", "느린", "뒤처"])
        scored.sort(reverse=not asc)
        top = scored[:5]
        head = "진행률이 낮은" if asc else "진행률이 높은"
        lines = [f"· {i}: {p}%" for p, i in top]
        return f"{label} {head} 모델 {len(top)}종입니다.\n" + "\n".join(lines)

    # ── 4) 모델 수 / 목록 ──
    if any(k in t for k in ["몇 종", "몇종", "몇 개", "몇개", "모델 수", "목록", "리스트", "어떤 모델"]):
        want_dev = "개발" in t
        want_mass = "양산" in t
        if want_dev and not want_mass:
            ids = [_s(m.get("id")) for m in dev]
            return f"{label} 개발 모델은 {len(dev)}종입니다.\n{_fmt_models(ids)}"
        if want_mass and not want_dev:
            ids = [_s(m.get("id")) for m in mass]
            return f"{label} 양산 모델은 {len(mass)}종입니다.\n{_fmt_models(ids)}"
        return (f"{label} 전체 {len(models)}종입니다. 양산 {len(mass)}종, 개발 {len(dev)}종.")

    # ── 1) 프로젝트 요약 ──
    summary_words = ["현황", "상태", "어때", "어떻게", "요약", "알려줘", "정리"]
    bare = re.sub(r"\s+", "", t)
    is_bare_name = len(bare) <= 12 and not any(c.isdigit() for c in bare)
    if is_bare_name or any(k in t for k in summary_words):
        return _answer_project(label, proj, models, mass, dev, process_progress)

    return None


def _answer_model(m, process_progress, process_current):
    mid = _s(m.get("id"))
    if m.get("group") == "개발":
        proc = m.get("process") if isinstance(m.get("process"), list) else []
        if not _filled(proc):
            return (f"{mid}{_josa(mid)} 개발 모델이고, 공정 입력이 아직 없습니다. "
                    f"PO {int(m.get('po_qty') or 0)}대 / 출하 {int(m.get('shipped_qty') or 0)}대.")
        prog = process_progress(proc)
        done = sum(1 for st in proc
                   if _s(st.get("actual")) or _s(st.get("status")) == "완료")
        stage, expected = process_current(proc)
        line = f"{mid} ({_s(m.get('dev_type')) or '개발'}) {done}/{len(proc)}단계, 진행률 {prog}%입니다."
        if stage:
            line += f"\n다음 단계는 '{stage}'"
            line += f" (예정 {expected})." if expected else "이고 예정일은 아직 없습니다."
        note = _s(m.get("note"))
        if note:
            line += f"\n비고: {note[:80]}"
        return line

    po = int(m.get("po_qty") or 0)
    sh = int(m.get("shipped_qty") or 0)
    price = int(m.get("price") or 0)
    if po <= 0:
        return (f"{mid}{_josa(mid)} 양산 모델이고, PO 수량이 아직 등록되지 않아 진행률을 낼 수 없습니다. "
                f"누적 출하 {sh}대, 판가 ${price:,}.")
    prog = round(sh * 100 / po)
    line = (f"{mid}{_josa(mid)} PO {po}대 중 {sh}대 출하해 진행률 {prog}%입니다. "
            f"잔량 {max(0, po - sh)}대, 판가 ${price:,}.")
    wp = m.get("weekly_plan") or {}
    if wp:
        last_mo = sorted(wp.keys())[-1]
        cells = wp[last_mo] or {}
        tp = sum(int((c or {}).get("plan") or 0) for c in cells.values())
        ta = sum(int((c or {}).get("actual") or 0) for c in cells.values())
        line += f"\n{last_mo} 주차 계획 {tp}대 / 실적 {ta}대."
    note = _s(m.get("note"))
    if note:
        line += f"\n비고: {note[:80]}"
    return line


def _answer_project(label, proj, models, mass, dev, process_progress):
    ws = proj.get("weekly_summary") or {}
    lines = [f"{label}{_josa(label)} 모델 {len(models)}종입니다 (양산 {len(mass)}종, 개발 {len(dev)}종)."]

    for g in ("양산", "개발"):
        grp = ws.get(g) or {}
        po = int(grp.get("po_qty") or 0)
        act = int(grp.get("actual_total") or 0)
        rem = int(grp.get("remaining") or 0)
        if po or act:
            pct = round(act * 100 / po) if po else 0
            lines.append(f"{g}: PO {po:,}대 중 {act:,}대 출하 ({pct}%), 잔량 {rem:,}대.")

    # 최근 실적이 있는 주차
    latest = None
    for g in ("양산", "개발"):
        for w, c in (((ws.get(g) or {}).get("weeks")) or {}).items():
            if (c or {}).get("actual"):
                n = int(re.sub(r"\D", "", w) or 0)
                if latest is None or n > latest[0]:
                    latest = (n, w)
    if latest:
        w = latest[1]
        m_cell = ((ws.get("양산") or {}).get("weeks") or {}).get(w) or {}
        d_cell = ((ws.get("개발") or {}).get("weeks") or {}).get(w) or {}
        lines.append(
            f"가장 최근 실적은 {w} 주차로 양산 {int(m_cell.get('actual') or 0)}대, "
            f"개발 {int(d_cell.get('actual') or 0)}대입니다."
        )

    scored = [p for p in (_model_progress(m, process_progress) for m in models) if p is not None]
    if scored:
        lines.append(f"진행률 집계 대상 {len(scored)}종의 평균은 {round(sum(scored) / len(scored))}%입니다.")

    issues = [m for m in models if _s(m.get("issues"))]
    if issues:
        lines.append(f"이슈가 등록된 모델은 {len(issues)}종입니다.")

    return "\n".join(lines)
