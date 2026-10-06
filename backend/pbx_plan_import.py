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
# 주차 블록의 세 번째 칸 — 계획을 못 채운 이유
NOTE_WORDS = {"미달사유", "사유", "비고", "미달이유", "reason", "note"}

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

def _find_week_header(ws, max_scan=400):
    """'W##' 이 2개 이상 있는 행 → (행번호, {열: 주차번호})

    예전에는 위에서 30줄까지만 봤다. 하바플레이트 현황 파일은 주차표가
    84행에 있어서 통째로 못 읽었다. 시트 끝까지 보되 가장 많이 걸리는
    줄 하나만 고른다 — 같은 수면 위쪽을 쓴다(아래는 보통 합계·메모다).
    """
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
    """주차 머리글 아래 줄 → (행번호, {주차번호: (계획열, 실적열)}, {주차번호: 사유열})

    OneView 양식은 주차 한 칸이 '계획 · 실적 · 미달 사유' 세 칸이다.
    계획을 못 채운 주에 왜 그런지 바로 옆에 적게 하려는 것이라, 숫자와
    같이 읽어야 쓸모가 있다.
    """
    for r in (week_row + 1, week_row):
        pairs, notes = {}, {}
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
            return r, pairs, notes
    # Plan/Actual 글자가 없으면 '주차열 = 계획, 그 옆 = 실적' 으로 본다
    pairs = {n: (c, c + 1) for c, n in week_cols.items()}
    return week_row + 1, pairs, {}


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


def parse_sheet(ws, month=None):
    """시트 하나 → {'month','weeks',[rows]} 또는 None.

    month 를 주면 그 달 주차만 읽는다. 한 표가 9월(W40)과 10월(W41~44)에
    걸쳐 있을 때 한 달이 버려지지 않게 하려는 것이다.
    """
    hdr = _find_week_header(ws)
    if not hdr:
        return None
    week_row, week_cols = hdr
    sub_row, pairs, notes = _find_sub_header(ws, week_row, week_cols)
    if not pairs:
        return None
    model_col = _find_model_col(ws, sub_row, min(week_cols))
    if not model_col:
        return None

    # 달을 지정해 부르면 그대로 쓴다 (한 표가 두 달에 걸친 경우)
    if month:
        try:
            own_m = set(_wcal.get_month_weeks(month))
        except Exception:
            own_m = set()
        if not own_m or not any(f"W{n:02d}" in own_m for n in pairs):
            return None
        return _rows_of(ws, sub_row, model_col, month,
                        {n: v for n, v in pairs.items()
                         if f"W{n:02d}" in own_m}, notes)

    # 이 시트가 어느 달 자료인가.
    #
    # 1) 시트 이름이 'YYYY-MM' 이면 그걸 쓴다. OneView 가 내려주는 양식이
    #    그렇게 적는다. 주차 번호만 보면 연도를 알 수 없어서, 2027-03 처럼
    #    해가 넘어간 달은 올해(2026) W09 로 읽혀 통째로 버려졌다.
    #    이름을 그냥 믿지는 않는다 — 그 달이 실제로 가진 주차인지 맞춰 본다.
    # 2) 아니면 예전처럼 주차 번호로 투표한다 (남이 만든 파일들).
    month = ""
    m_name = re.match(r"^\s*(\d{4})-(\d{1,2})\s*$", _s(ws.title))
    if m_name:
        cand = "%04d-%02d" % (int(m_name.group(1)), int(m_name.group(2)))
        try:
            own_c = set(_wcal.get_month_weeks(cand))
        except Exception:
            own_c = set()
        if own_c and any(f"W{n:02d}" in own_c for n in pairs):
            month = cand
    if not month:
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
    return _rows_of(ws, sub_row, model_col, month, pairs, notes)


def _rows_of(ws, sub_row, model_col, month, pairs, notes=None):
    """머리글을 다 찾은 뒤 실제 줄을 읽는다."""
    notes = notes or {}
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
        "week_notes": _week_notes(ws, sub_row, model_col, pairs),
    }


def _week_notes(ws, sub_row, model_col, pairs):
    """'미달 사유' 줄 → {'W41': '자재 지연', ...}

    사유는 모델 한 줄씩이 아니라 **그 주 합계**에 붙는다. 양식에서는
    모델 목록이 '합계' 줄에서 끝나고, 그 아래 '미달 사유' 줄에 주차마다
    한 칸씩 있다. 화면의 '계획 미달 — 왜 못 채웠는지' 와 같은 단위다.
    """
    out = {}
    wide = max(model_col, 4)          # 라벨이 왼쪽 어느 칸에 있어도 잡는다
    for r in range(sub_row + 1, ws.max_row + 1):
        head = "".join(_s(ws.cell(r, c).value) for c in range(1, wide + 1))
        if re.sub(r"\s+", "", head).lower() not in NOTE_WORDS:
            continue
        for n, (pc, _ac) in pairs.items():
            txt = _s(ws.cell(r, pc).value).replace("\n", " ").strip()
            if txt:
                out[f"W{n:02d}"] = txt
        break
    return out


def parse_sheet_all(ws):
    """시트 하나가 걸친 달을 **전부** → [parsed, ...] (이른 달부터).

    하바 현황 파일의 주차표는 W40~W44 다. 달력으로는 W40 이 9월,
    W41~W44 가 10월이라 한 표가 두 달에 걸친다. 대표 달 하나만 보면
    9월이 통째로 사라진다.
    """
    hdr = _find_week_header(ws)
    if not hdr:
        return []
    week_row, week_cols = hdr
    sub_row, pairs, _notes = _find_sub_header(ws, week_row, week_cols)
    if not pairs:
        return []
    months = []
    for n in pairs:
        mo = _wcal.month_of_week(f"W{n:02d}")
        if mo and mo not in months:
            months.append(mo)
    out = []
    for mo in sorted(months):
        got = parse_sheet(ws, month=mo)
        if got and got["rows"]:
            out.append(got)
    return out


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
        # 하바처럼 주차별 스냅샷이 34장 들어 있으면 같은 달 시트가 여럿이다.
        # 순서대로 첫 번째를 집으면 가장 **오래된** 스냅샷을 쓰게 된다.
        # 줄이 많은 쪽, 같으면 뒤쪽(최신) 시트를 쓴다.
        cands = [(i, g) for i, g in enumerate(found) if g["month"] == month]
        if not cands:
            return None
        cands.sort(key=lambda x: (len(x[1]["rows"]), x[0]))
        return cands[-1][1]
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
            # 파트넘버 칸. '파트넘버로 찾는다' 고 적어 두고 정작 이 칸을
            # 안 보고 있었다 — id·모델명만 봤다.
            raw_pn = _s(m.get("part_number"))
            # 별칭 — 같은 물건을 거래처마다 다른 품번으로 부른다.
            # 복사본 엑셀의 853-800575-009 가 우리 714-025898-009 다.
            alts = [_s(a) for a in (m.get("aliases") or []) if _s(a)]

            blob = " ".join([raw_id, raw_name, raw_pn] + alts)
            for one in [raw_id, raw_pn] + alts:
                self._add_id(_norm(one), m)
            for pn in PN_RE.findall(blob):
                self._add_id(_norm(pn), m)
            for d in re.findall(r"\b\d{6,9}\b", blob):
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
