"""'Plan and Actual' 형태의 출하계획 엑셀에서 주차별 계획/실적을 읽는다.

파워박스팀이 매주 쓰는 'PBX 9월 출하계획' 파일이 대상이다. 시트 구조는

        (4행)          W36        W37        W38   ...   TOTAL
        (5행)  No. Customer Model  Plan Actual Plan Actual ...
        (6행~)  1  Lam  AETHER GDX 925-800083-394  40  41  50  0 ...
        (합계행) Total                              49  52  77  0 ...

열 위치를 고정하지 않는다. 'W##' 이 2개 이상 있는 행을 찾아 주차 머리글로 잡고,
그 아래 행에서 Plan/Actual 짝을 찾는다. 시트 이름('..._Sep')도 믿지 않는다.
주차 번호를 week_calendar 에 물어서 어느 달 자료인지 스스로 판단한다.

TOTAL 열은 읽지 않는다. 실제 파일에서 이 열의 수식이 깨져
계획 합계가 400 대신 333 으로 나오는 걸 확인했다. 합계는 주차 값을 더해서 만든다.
"""

from __future__ import annotations

import collections
import re

import week_calendar as _wcal

WEEK_RE = re.compile(r"^W\s*(\d{1,2})$", re.I)
PLAN_WORDS = {"plan", "계획", "계획수량"}
ACT_WORDS = {"actual", "실적", "출하", "출하실적"}
STOP_WORDS = {"total", "grand total", "합계", "총계", "소계", "sum"}
MODEL_WORDS = {"model", "모델", "모델명", "품명", "part no.", "part no", "품번"}

# 품번처럼 보이는 토막. '925-800083-394', '575-B68653-XXXX', '02-429411-00'
PN_RE = re.compile(r"\b([0-9A-Za-z]{2,3}-[0-9A-Za-z]{5,6}-[0-9A-Za-z]{2,6}[A-Za-z]?)\b")


def _s(v):
    return "" if v is None else str(v).strip()


def _num(v):
    if v is None or v == "":
        return None
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        try:
            return int(round(v))
        except Exception:
            return None
    t = str(v).strip().replace(",", "")
    if t in ("", "-", "N/A", "n/a"):
        return None
    try:
        return int(round(float(t)))
    except Exception:
        return None


def _norm(v):
    """비교용 정규화 — 영숫자만 남기고 대문자로."""
    return re.sub(r"[^0-9A-Z]", "", _s(v).upper())


# ────────────────────────────────────────────────────────── 시트 읽기

def _find_week_header(ws, max_scan=30):
    """'W##' 이 2개 이상 있는 행 → (행번호, {열: 주차번호})"""
    best = None
    for r in range(1, min(ws.max_row, max_scan) + 1):
        hits = {}
        for c in range(1, ws.max_column + 1):
            m = WEEK_RE.match(_s(ws.cell(r, c).value))
            if m:
                n = int(m.group(1))
                if 1 <= n <= 53:
                    hits[c] = n
        if len(hits) >= 2 and (best is None or len(hits) > len(best[1])):
            best = (r, hits)
    return best


def _find_sub_header(ws, week_row, week_cols):
    """주차 머리글 아래에서 Plan/Actual 짝을 찾는다 → (행번호, {주차번호: (계획열, 실적열)})"""
    first_wc = min(week_cols)
    for r in (week_row + 1, week_row):
        pairs = {}
        for c, n in sorted(week_cols.items()):
            kind = {}
            # 병합 때문에 주차 라벨은 계획 열 위에만 있다. 그 열부터 오른쪽으로 3칸.
            for off in range(0, 3):
                t = _s(ws.cell(r, c + off).value).lower()
                if t in PLAN_WORDS and "plan" not in kind:
                    kind["plan"] = c + off
                elif t in ACT_WORDS and "actual" not in kind:
                    kind["actual"] = c + off
            if "plan" in kind:
                pairs[n] = (kind["plan"], kind.get("actual"))
        if len(pairs) >= 2:
            return r, pairs
    # Plan/Actual 글자가 없으면 '주차열 = 계획, 그 옆 = 실적' 으로 본다
    pairs = {n: (c, c + 1) for c, n in week_cols.items()}
    return week_row + 1, pairs


def _find_model_col(ws, sub_row, first_week_col):
    """모델 열 — 머리글에 Model 이라 적힌 열, 없으면 주차 앞 마지막 글자 열."""
    for c in range(1, first_week_col):
        if _s(ws.cell(sub_row, c).value).lower() in MODEL_WORDS:
            return c
    best, best_n = None, 0
    for c in range(1, first_week_col):
        n = sum(1 for r in range(sub_row + 1, min(ws.max_row, sub_row + 40) + 1)
                if _s(ws.cell(r, c).value) and _num(ws.cell(r, c).value) is None)
        if n > best_n:
            best, best_n = c, n
    return best


def parse_sheet(ws):
    """시트 하나 → {'month','weeks',[rows]} 또는 None."""
    hdr = _find_week_header(ws)
    if not hdr:
        return None
    week_row, week_cols = hdr
    sub_row, pairs = _find_sub_header(ws, week_row, week_cols)
    if not pairs:
        return None
    model_col = _find_model_col(ws, sub_row, min(week_cols))
    if not model_col:
        return None

    # 주차 번호로 이 시트가 어느 달 자료인지 정한다 (시트 이름은 믿지 않는다)
    votes = collections.Counter()
    for n in pairs:
        mo = _wcal.month_of_week(f"W{n:02d}")
        if mo:
            votes[mo] += 1
    if not votes:
        return None
    month = votes.most_common(1)[0][0]
    # 그 달이 실제로 가진 주차만 남긴다
    own = set(_wcal.get_month_weeks(month))
    pairs = {n: v for n, v in pairs.items() if f"W{n:02d}" in own}
    if not pairs:
        return None

    rows = []
    for r in range(sub_row + 1, ws.max_row + 1):
        label = _s(ws.cell(r, model_col).value).replace("\n", " ").strip()
        # 라벨 칸이 비어도 왼쪽 어딘가에 합계 글자가 있으면 거기서 끊는다
        line = " ".join(_s(ws.cell(r, c).value) for c in range(1, model_col + 1)).lower()
        if any(w in line for w in STOP_WORDS):
            break
        if not label:
            continue
        weeks, any_val = {}, False
        for n, (pc, ac) in sorted(pairs.items()):
            p = _num(ws.cell(r, pc).value)
            a = _num(ws.cell(r, ac).value) if ac else None
            weeks[f"W{n:02d}"] = {"plan": p or 0, "actual": a or 0}
            if p is not None or a is not None:
                any_val = True
        if not any_val:
            continue
        rows.append({"row": r, "label": label, "weeks": weeks})

    return {
        "sheet": ws.title,
        "month": month,
        "weeks": [f"W{n:02d}" for n in sorted(pairs)],
        "rows": rows,
    }


def parse(wb, month=None):
    """워크북에서 쓸 만한 시트를 모두 읽어 월별로 돌려준다.

    month 를 주면 그 달 시트만, 없으면 가장 최근 달 시트를 고른다.
    """
    found = []
    for ws in wb.worksheets:
        try:
            got = parse_sheet(ws)
        except Exception:
            got = None
        if got and got["rows"]:
            found.append(got)
    if not found:
        return None
    if month:
        for g in found:
            if g["month"] == month:
                return g
        return None
    found.sort(key=lambda g: (g["month"], len(g["rows"])))
    return found[-1]


def sheet_months(wb):
    """어떤 달 자료가 들어 있는지만 훑는다."""
    out = []
    for ws in wb.worksheets:
        try:
            got = parse_sheet(ws)
        except Exception:
            continue
        if got and got["rows"]:
            out.append({"sheet": got["sheet"], "month": got["month"],
                        "weeks": got["weeks"], "rows": len(got["rows"])})
    return out


# ────────────────────────────────────────────────────────── 모델 맞추기

class Matcher:
    """등록된 모델과 엑셀 라벨을 맞춘다.

    엑셀 라벨은 'AETHER GDX 925-800083-394' 처럼 이름과 품번이 섞여 있고,
    등록 쪽도 'KIYO GX 575-B68653-XXXX' 처럼 품번 칸에 이름이 들어간 게 있다.
    그래서 양쪽 모두에서 품번처럼 생긴 토막을 뽑아 색인을 만든다.
    """

    def __init__(self, models):
        self.by_id = {}
        self.by_name = collections.defaultdict(list)
        self.prefix = []          # ('575B68653', model) — 뒤가 X 로 채워진 계열 품번
        for m in models:
            raw_id, raw_name = _s(m.get("id")), _s(m.get("name"))
            self._add_id(_norm(raw_id), m)
            for pn in PN_RE.findall(raw_id) + PN_RE.findall(raw_name):
                self._add_id(_norm(pn), m)
            for d in re.findall(r"\b\d{6,9}\b", raw_id + " " + raw_name):
                self._add_id(_norm(d), m)
            n = _norm(raw_name)
            if n:
                self.by_name[n].append(m)
        self.prefix.sort(key=lambda t: -len(t[0]))

    def _add_id(self, key, m):
        if not key:
            return
        self.by_id.setdefault(key, m)
        if key.endswith("X") and len(key.rstrip("X")) >= 8:
            self.prefix.append((key.rstrip("X"), m))

    def _by_id(self, key):
        if not key:
            return None, None
        if key in self.by_id:
            return self.by_id[key], "품번"
        for p, m in self.prefix:
            if key.startswith(p):
                return m, "품번(계열)"
        for rk, m in self.by_id.items():
            if len(key) == len(rk) and all(a == b or a == "X" or b == "X"
                                           for a, b in zip(key, rk)):
                return m, "품번(X)"
        return None, None

    def match(self, text, group=None):
        """→ (모델, 어떻게 찾았는지) · 못 찾으면 (None, 사유)"""
        t = _s(text).replace("\n", " ")
        if not t:
            return None, "빈칸"
        for pn in PN_RE.findall(t):
            m, how = self._by_id(_norm(pn))
            if m:
                return m, how
        rest = PN_RE.sub(" ", t)
        rest = re.sub(r"[()/\-]", " ", rest)
        rest = re.sub(r"\b\d+\b", " ", rest)
        cands = self.by_name.get(_norm(rest), [])
        if group:
            cands = [c for c in cands if c.get("group") == group] or cands
        if len(cands) == 1:
            return cands[0], "이름"
        if len(cands) > 1:
            return None, f"이름 중복 {len(cands)}종"
        m, how = self._by_id(_norm(t))
        if m:
            return m, how
        return None, "등록 안 됨"
