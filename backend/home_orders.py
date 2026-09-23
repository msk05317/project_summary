"""사장님 지시사항 — 앱 홈 맨 위 노란 카드.

줄마다 따로다. 어떤 건 '9/30까지', 어떤 건 '매일 점검', 어떤 건 기한이 없다.
카드 하나에 등록일 하나만 붙이면 그 차이가 사라진다.

  due_kind : date(날짜까지) · none(기한 없음) · daily(매일) · weekly(매주)
  done     : 완료하면 앱에서 바로 내려간다 (admin 에는 남아서 되돌린다)

정렬은 '지금 뭘 해야 하나' 순서다 — 기한 지남 → 기한 임박 → 반복 → 기한 없음.
"""
from __future__ import annotations

import datetime as _dt
import json
import re
import uuid
from pathlib import Path

KINDS = ("date", "none", "daily", "weekly")
KIND_LABEL = {"date": "날짜까지", "none": "기한 없음", "daily": "매일", "weekly": "매주"}
MAX_ITEMS = 50
MAX_TEXT = 300
_DATE_RE = re.compile(r"^20\d\d-\d{2}-\d{2}$")


def _s(v) -> str:
    return "" if v is None else str(v).strip()


def _date(v) -> str:
    t = _s(v)[:10]
    if not _DATE_RE.match(t):
        return ""
    try:
        _dt.date.fromisoformat(t)
    except ValueError:
        return ""
    return t


def _today() -> str:
    return _dt.date.today().isoformat()


def new_id() -> str:
    return "o_" + uuid.uuid4().hex[:10]


def normalize(items, today: str = "") -> list[dict]:
    """화면에서 온 줄들을 저장할 모양으로. 빈 줄은 버린다."""
    today = _date(today) or _today()
    out = []
    for raw in (items or []):
        if not isinstance(raw, dict):
            continue
        text = _s(raw.get("text"))[:MAX_TEXT]
        if not text:
            continue
        kind = _s(raw.get("due_kind")).lower()
        if kind not in KINDS:
            kind = "none"
        due = _date(raw.get("due")) if kind == "date" else ""
        if kind == "date" and not due:
            # 날짜를 안 적었으면 기한 없음으로 둔다. 0000-00-00 으로 저장하면
            # 앱에서 '지남'으로 빨갛게 뜬다.
            kind = "none"
        done = bool(raw.get("done"))
        out.append({
            "id": _s(raw.get("id")) or new_id(),
            "text": text,
            "due_kind": kind,
            "due": due,
            "created": _date(raw.get("created")) or today,
            "done": done,
            "done_at": (_date(raw.get("done_at")) or today) if done else "",
        })
        if len(out) >= MAX_ITEMS:
            break
    return out


def _days_left(due: str, today: str) -> int | None:
    if not due:
        return None
    return (_dt.date.fromisoformat(due) - _dt.date.fromisoformat(today)).days


def _md(iso: str) -> str:
    m, d = iso[5:7], iso[8:10]
    return f"{int(m)}/{int(d)}"


def badge(item: dict, today: str) -> dict:
    """앱에서 줄 뒤에 붙는 꼬리표. tone 이 색을 정한다."""
    kind = item.get("due_kind")
    if kind in ("daily", "weekly"):
        return {"text": KIND_LABEL[kind], "tone": "repeat"}
    if kind == "date" and item.get("due"):
        n = _days_left(item["due"], today)
        if n < 0:
            return {"text": f"지남 · D+{-n}", "tone": "late"}
        if n == 0:
            return {"text": f"오늘 · {_md(item['due'])}", "tone": "late"}
        tone = "late" if n <= 3 else ("warn" if n <= 7 else "plain")
        return {"text": f"D-{n} · {_md(item['due'])}", "tone": tone}
    return {"text": f"{_md(item['created'])} 등록", "tone": "plain"}


def _sort_key(item: dict, today: str):
    """지남(0) → 기한 임박(1) → 반복(2) → 기한 없음(3)."""
    kind = item.get("due_kind")
    if kind == "date" and item.get("due"):
        n = _days_left(item["due"], today)
        if n < 0:
            return (0, n, item.get("created", ""))       # 더 오래 지난 것이 위
        return (1, n, item.get("created", ""))           # 더 급한 것이 위
    if kind in ("daily", "weekly"):
        return (2, 0 if kind == "daily" else 1, item.get("created", ""))
    # 기한 없음 — 최근에 들어온 지시가 위
    return (3, 0, "9999" if not item.get("created") else _neg_date(item["created"]))


def _neg_date(iso: str) -> str:
    """날짜를 거꾸로 정렬하려고 뒤집은 문자열."""
    try:
        d = _dt.date.fromisoformat(iso)
    except ValueError:
        return "9999-99-99"
    return str(99999999 - int(d.strftime("%Y%m%d")))


def for_app(items, today: str = "") -> list[dict]:
    """앱 홈에 내려보낼 줄들 — 완료는 빼고, 급한 것부터."""
    today = _date(today) or _today()
    live = [i for i in normalize(items, today) if not i.get("done")]
    live.sort(key=lambda i: _sort_key(i, today))
    out = []
    for i in live:
        b = badge(i, today)
        out.append({**i, "badge": b["text"], "tone": b["tone"],
                    "days_left": _days_left(i.get("due", ""), today)})
    return out


def load(path: Path) -> dict:
    try:
        raw = json.loads(Path(path).read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {"items": [], "updated_at": ""}
    except Exception as e:
        raise ValueError(f"지시사항 파일을 읽지 못했습니다: {e}")
    if not isinstance(raw, dict):
        return {"items": [], "updated_at": ""}
    raw["items"] = normalize(raw.get("items"))
    return raw


def save(path: Path, items, today: str = "") -> dict:
    data = {"items": normalize(items, today),
            "updated_at": _dt.datetime.now().isoformat(timespec="seconds")}
    p = Path(path)
    tmp = p.with_suffix(p.suffix + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(p)
    return data
