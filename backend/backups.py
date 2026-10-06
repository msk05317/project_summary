# -*- coding: utf-8 -*-
"""일일 백업.

데이터가 사라지는 사고는 대개 사람이 낸다 — 엑셀을 잘못 올려서 모델이
통째로 바뀌거나, 되돌리기를 눌렀는데 그 사이 제대로 들어간 것까지 같이
잃는다. models.json 에만 있던 '저장 직전 백업' 10개는 그런 사고 중
*방금* 난 것만 막는다. 하루에 스무 번 저장하면 열 개가 전부 오늘 것이라,
어제 상태로 돌아갈 방법이 없었다.

그래서 하루 한 벌, 그날의 데이터 전부를 tar.gz 한 덩이로 남긴다.

### 안 지우는 것이 제일 중요하다

이 모듈은 `/data/backups/` 안에서만 파일을 지운다. 그 밖의 무엇도
건드리지 않는다 — 운영 데이터, note_assets, uploads, 기존 .auto_/.bak
파일 전부 그대로 둔다. 되돌리기도 덮어쓰기 전에 먼저 한 벌 떠 둔다.

### 언제 도는가

fly.toml 에 auto_stop_machines = true 가 걸려 있다. 아무도 안 쓰면
서버가 꺼지므로, 자정에 깨어 있을 거라고 기대하는 스케줄러는 못 쓴다.
대신 요청이 들어올 때 '오늘 것이 있나' 를 보고 없으면 만든다. 아침에
누가 앱을 처음 열면 그때 그날 백업이 생긴다.

### 얼마나 두는가 (GFS)

    일간  30일   — 월 마감 한 사이클. 9월 매입을 10월 중순에 고치는 일이 있다.
    주간  12주   — 각 주의 첫 백업. 분기를 덮는다.
    월간  24개월 — 각 달의 첫 백업. 작년 같은 달과 비교하려면 2년이 필요하다.

한 벌이 압축 후 150KB 남짓이라 66벌 모두 10MB 안쪽이다. 볼륨은 974MB다.
"""

from __future__ import annotations

import datetime as _dt
import json
import os
import re
import shutil
import tarfile
import threading
from pathlib import Path

# ── 설정 ────────────────────────────────────────────────────────────
DAILY_KEEP_DAYS = 30
WEEKLY_KEEP_WEEKS = 12
MONTHLY_KEEP_MONTHS = 24

#: 아무리 오래됐어도 이 개수 밑으로는 안 지운다. 날짜 계산이 틀려도
#: 전부 날아가지는 않게 하는 바닥이다.
MIN_KEEP = 5

#: 한 덩이가 이보다 크면 뭔가 잘못된 것이다 (apk 가 섞였다거나).
MAX_SNAPSHOT_BYTES = 80 * 1024 * 1024

#: 백업에 넣지 않는 것. apk 는 60MB 이고 git 에서 다시 만들 수 있다.
EXCLUDE_NAMES = {"app_release.apk"}
EXCLUDE_SUFFIXES = (".part", ".tar", ".tar.gz", ".tgz", ".apk", ".log")

#: 이름이 이 꼴이면 백업의 백업이라 넣지 않는다.
_DERIVED = re.compile(r"\.(auto|bak)[_.-]|\.bak$|\.bak_", re.I)

_NAME_RE = re.compile(
    r"^(\d{4})-(\d{2})-(\d{2})(?:_\d{6})?(?:_[0-9a-z\-]{1,24})?\.tar\.gz$")
_SAFE_MEMBER = re.compile(r"^[A-Za-z0-9._\-]{1,128}$")

_lock = threading.Lock()
_checked_on = ""          # 이 프로세스가 마지막으로 확인한 날짜


# ── 경로 ────────────────────────────────────────────────────────────
def backups_dir(data_dir) -> Path:
    d = Path(data_dir) / "backups"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _today() -> str:
    return _dt.date.today().isoformat()


# ── 무엇을 담을까 ────────────────────────────────────────────────────
def source_files(data_dir) -> list:
    """백업에 넣을 파일. DATA_DIR 바로 밑의 .json 만 — 폴더는 안 따라간다.

    목록을 코드에 박지 않고 그때그때 훑는다. 나중에 데이터 파일이 하나
    늘었을 때 아무도 이 목록을 안 고쳐서 그 파일만 백업이 없는 일이
    생기지 않게 하려는 것이다.
    """
    root = Path(data_dir)
    out = []
    for p in sorted(root.glob("*.json")):
        if not p.is_file():
            continue
        if p.name in EXCLUDE_NAMES or _DERIVED.search(p.name):
            continue
        if p.name.endswith(EXCLUDE_SUFFIXES):
            continue
        out.append(p)
    return out


# ── 한 벌 뜨기 ──────────────────────────────────────────────────────
def snapshot(data_dir, label: str = "") -> dict:
    """오늘 것 한 벌. 이미 있으면 덮어쓴다 (그날의 마지막 상태를 남긴다).

    .part 로 다 쓴 뒤 열어서 읽히는지 확인하고 나서 제자리로 옮긴다.
    중간에 죽어도 반쯤 쓰다 만 파일이 '백업' 행세를 하지 않는다.
    """
    root = Path(data_dir)
    out_dir = backups_dir(root)
    files = source_files(root)
    if not files:
        return {"ok": False, "reason": "담을 파일이 없습니다", "name": ""}

    # 라벨이 붙은 것(되돌리기 직전 등)은 시각까지 넣는다. 같은 날 두 번
    # 되돌리면 앞의 것을 덮어써서, 되돌리기 전으로 다시 못 가던 적이 있다.
    stem = _today()
    if label:
        stem += _dt.datetime.now().strftime("_%H%M%S")
        stem += "_" + re.sub(r"[^0-9a-z\-]", "", label.lower())[:24]
    final = out_dir / (stem + ".tar.gz")
    tmp = out_dir / (stem + ".tar.gz.part")

    try:
        with tarfile.open(tmp, "w:gz") as tf:
            for p in files:
                tf.add(str(p), arcname=p.name)
            meta = {
                "made_at": _dt.datetime.now().isoformat(timespec="seconds"),
                "label": label,
                "files": [{"name": p.name, "bytes": p.stat().st_size} for p in files],
            }
            raw = json.dumps(meta, ensure_ascii=False, indent=2).encode("utf-8")
            info = tarfile.TarInfo("_backup_meta.json")
            info.size = len(raw)
            info.mtime = int(_dt.datetime.now().timestamp())
            import io as _io
            tf.addfile(info, _io.BytesIO(raw))

        size = tmp.stat().st_size
        if size > MAX_SNAPSHOT_BYTES:
            tmp.unlink(missing_ok=True)
            return {"ok": False, "reason": "백업이 너무 큽니다 (%d bytes)" % size,
                    "name": ""}
        # 읽히는지 확인하고 나서야 제자리로 옮긴다
        with tarfile.open(tmp, "r:gz") as tf:
            got = set(tf.getnames())
        want = {p.name for p in files} | {"_backup_meta.json"}
        if got != want:
            tmp.unlink(missing_ok=True)
            return {"ok": False, "reason": "백업 내용이 안 맞습니다", "name": ""}

        os.replace(tmp, final)
    except Exception as e:
        try:
            tmp.unlink(missing_ok=True)
        except Exception:
            pass
        return {"ok": False, "reason": "%s" % e, "name": ""}

    return {"ok": True, "name": final.name, "bytes": final.stat().st_size,
            "files": len(files)}


# ── 얼마나 둘까 ─────────────────────────────────────────────────────
def _date_of(name: str):
    m = _NAME_RE.match(name)
    if not m:
        return None
    try:
        return _dt.date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
    except ValueError:
        return None


def plan_prune(names, today=None) -> dict:
    """어느 것을 남기고 어느 것을 지울지. 지우기 전에 이것만 따로 볼 수 있다.

    남기는 규칙 — 하나라도 걸리면 남는다:
      · 최근 30일 안
      · 그 주(ISO)의 첫 백업이고, 최근 12주 안
      · 그 달의 첫 백업이고, 최근 24개월 안
    """
    today = today or _dt.date.today()
    dated = []
    for n in names:
        d = _date_of(n)
        if d:
            dated.append((d, n))
    dated.sort()

    first_of_week, first_of_month = {}, {}
    for d, n in dated:
        wk = (d.isocalendar()[0], d.isocalendar()[1])
        first_of_week.setdefault(wk, n)
        first_of_month.setdefault((d.year, d.month), n)

    def months_ago(d):
        return (today.year - d.year) * 12 + (today.month - d.month)

    keep, drop = [], []
    for d, n in dated:
        age = (today - d).days
        wk = (d.isocalendar()[0], d.isocalendar()[1])
        why = ""
        if age < 0 or age < DAILY_KEEP_DAYS:
            why = "일간"
        elif first_of_week.get(wk) == n and age < WEEKLY_KEEP_WEEKS * 7:
            why = "주간"
        elif (first_of_month.get((d.year, d.month)) == n
              and months_ago(d) < MONTHLY_KEEP_MONTHS):
            why = "월간"
        (keep if why else drop).append((n, why or "기간 지남"))

    # 바닥: 날짜 계산이 틀려도 최소 몇 벌은 남긴다 (최신 것부터)
    if len(keep) < MIN_KEEP and drop:
        drop.sort(key=lambda x: x[0], reverse=True)
        while len(keep) < MIN_KEEP and drop:
            n, _ = drop.pop(0)
            keep.append((n, "바닥"))

    return {"keep": [{"name": n, "why": w} for n, w in sorted(keep)],
            "drop": [{"name": n, "why": w} for n, w in sorted(drop)]}


def prune(data_dir, dry_run: bool = False) -> dict:
    """오래된 백업 정리. **backups 폴더 안에서만** 지운다."""
    out_dir = backups_dir(data_dir)
    names = [p.name for p in out_dir.iterdir()
             if p.is_file() and _NAME_RE.match(p.name)]
    plan = plan_prune(names)
    removed, freed = [], 0
    if not dry_run:
        for row in plan["drop"]:
            p = out_dir / os.path.basename(row["name"])
            # 두 번 확인한다 — 경로가 backups 안이고 이름 꼴이 맞을 때만
            if p.parent.resolve() != out_dir.resolve() or not _NAME_RE.match(p.name):
                continue
            try:
                freed += p.stat().st_size
                p.unlink()
                removed.append(p.name)
            except Exception:
                pass
    # 다 쓰지 못한 .part 는 하루 지나면 치운다
    cutoff = _dt.datetime.now().timestamp() - 86400
    for p in out_dir.glob("*.part"):
        try:
            if p.stat().st_mtime < cutoff:
                p.unlink()
        except Exception:
            pass
    return {"kept": len(plan["keep"]), "removed": removed,
            "freed_bytes": freed, "plan": plan}


# ── 하루 한 번 ──────────────────────────────────────────────────────
def has_today(data_dir) -> bool:
    t = _today()
    for p in backups_dir(data_dir).glob("%s*.tar.gz" % t):
        if p.is_file():
            return True
    return False


def ensure_today(data_dir) -> dict:
    """오늘 것이 없으면 만들고 정리한다. 요청 처리 중에 불려도 안전하게.

    서버가 켜져 있는 동안 하루에 한 번만 실제로 확인한다. 이미 확인한
    날이면 파일 시스템도 안 본다.
    """
    global _checked_on
    t = _today()
    if _checked_on == t:
        return {"skipped": "확인함"}
    if not _lock.acquire(blocking=False):
        return {"skipped": "다른 요청이 하는 중"}
    try:
        if _checked_on == t:
            return {"skipped": "확인함"}
        if has_today(data_dir):
            _checked_on = t
            return {"skipped": "오늘 것이 이미 있음"}
        res = snapshot(data_dir)
        if res.get("ok"):
            _checked_on = t
            res["prune"] = prune(data_dir)
        return res
    finally:
        _lock.release()


# ── 목록 · 되돌리기 ─────────────────────────────────────────────────
def list_backups(data_dir) -> list:
    out = []
    for p in sorted(backups_dir(data_dir).iterdir(), reverse=True):
        if not (p.is_file() and _NAME_RE.match(p.name)):
            continue
        st = p.stat()
        row = {"name": p.name, "bytes": st.st_size,
               "at": _dt.datetime.fromtimestamp(st.st_mtime).isoformat(timespec="seconds"),
               "files": []}
        try:
            with tarfile.open(p, "r:gz") as tf:
                row["files"] = sorted(n for n in tf.getnames()
                                      if n != "_backup_meta.json")
        except Exception as e:
            row["broken"] = str(e)
        out.append(row)
    return out


def peek(data_dir, name: str) -> dict:
    """그 백업 안이 어떤 모양인지. 되돌리기 전에 들여다보려고."""
    p = backups_dir(data_dir) / os.path.basename(name)
    if not p.exists() or not _NAME_RE.match(p.name):
        raise FileNotFoundError("그런 백업이 없습니다")
    out = {"name": p.name, "files": [], "meta": None}
    with tarfile.open(p, "r:gz") as tf:
        for m in tf.getmembers():
            if m.name == "_backup_meta.json":
                try:
                    out["meta"] = json.loads(tf.extractfile(m).read().decode("utf-8"))
                except Exception:
                    pass
                continue
            out["files"].append({"name": m.name, "bytes": m.size})
    out["files"].sort(key=lambda x: x["name"])
    return out


def restore(data_dir, name: str, only=None) -> dict:
    """백업으로 되돌린다.

    only 를 주면 그 파일만 바꾼다 — 통째로 되돌리면 그 사이에 제대로
    들어간 것까지 같이 잃는다.

    **덮어쓰기 전에 지금 상태를 먼저 한 벌 뜬다.** 되돌린 게 잘못이면
    다시 되돌릴 수 있어야 한다.
    """
    root = Path(data_dir)
    p = backups_dir(root) / os.path.basename(name)
    if not p.exists() or not _NAME_RE.match(p.name):
        raise FileNotFoundError("그런 백업이 없습니다")

    want = {str(x).strip() for x in (only or []) if str(x).strip()}

    # 먼저 다 읽어 둔다. 직전 백업을 뜨는 사이에 되돌릴 원본이 바뀌면
    # 안 되고, 하나라도 깨져 있으면 아무것도 안 건드리고 멈춰야 한다.
    payload, skipped = {}, []
    with tarfile.open(p, "r:gz") as tf:
        for m in tf.getmembers():
            n = m.name
            if n == "_backup_meta.json":
                continue
            # tar 안의 이름은 믿지 않는다 — 경로가 섞여 있으면 거른다
            if not m.isfile() or not _SAFE_MEMBER.match(n) or not n.endswith(".json"):
                skipped.append({"name": n, "why": "이름이 이상합니다"})
                continue
            if want and n not in want:
                continue
            src = tf.extractfile(m)
            if src is None:
                skipped.append({"name": n, "why": "읽지 못했습니다"})
                continue
            raw = src.read()
            try:
                json.loads(raw.decode("utf-8"))      # 깨진 걸 덮어쓰지 않는다
            except Exception as e:
                skipped.append({"name": n, "why": "JSON 이 깨졌습니다: %s" % e})
                continue
            payload[n] = raw

    # 읽을 게 하나도 없으면 지금 상태를 건드릴 이유가 없다
    if not payload:
        return {"ok": False, "name": p.name, "restored": [],
                "skipped": skipped, "pre_backup": "",
                "reason": "되돌릴 내용이 없습니다"}

    pre = snapshot(root, label="before-restore")

    done = []
    for n, raw in sorted(payload.items()):
        tmp = root / (n + ".restore_part")
        with open(tmp, "wb") as f:
            f.write(raw)
        os.replace(tmp, root / n)                     # 통째로 바뀐다
        done.append(n)

    return {"ok": True, "name": p.name, "restored": sorted(done),
            "skipped": skipped, "pre_backup": pre.get("name", "")}


# ── note_assets 는 주 1회 ───────────────────────────────────────────
#
# 첨부 이미지는 5.6MB 이고 추가만 되지 바뀌지 않는다. 매일 뜨면 66벌에
# 370MB 라 아깝다. 주 1회면 충분하고, 8주치라야 45MB 다.
ASSETS_DIRS = ("note_assets", "rag")
ASSETS_KEEP = 8
_ASSETS_RE = re.compile(r"^assets_(\d{4})-(\d{2})-(\d{2})\.tar\.gz$")


def ensure_assets_weekly(data_dir) -> dict:
    root = Path(data_dir)
    out_dir = backups_dir(root)
    have = sorted((p for p in out_dir.iterdir()
                   if p.is_file() and _ASSETS_RE.match(p.name)), reverse=True)
    if have:
        m = _ASSETS_RE.match(have[0].name)
        last = _dt.date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
        if (_dt.date.today() - last).days < 7:
            return {"skipped": "이번 주 것이 있음"}

    srcs = [root / d for d in ASSETS_DIRS if (root / d).is_dir()]
    if not srcs:
        return {"skipped": "담을 폴더가 없음"}

    final = out_dir / ("assets_%s.tar.gz" % _today())
    tmp = out_dir / (final.name + ".part")
    try:
        with tarfile.open(tmp, "w:gz") as tf:
            for s in srcs:
                tf.add(str(s), arcname=s.name)
        os.replace(tmp, final)
    except Exception as e:
        try:
            tmp.unlink(missing_ok=True)
        except Exception:
            pass
        return {"ok": False, "reason": str(e)}

    removed = []
    olds = sorted((p for p in out_dir.iterdir()
                   if p.is_file() and _ASSETS_RE.match(p.name)), reverse=True)
    for p in olds[ASSETS_KEEP:]:
        try:
            p.unlink(); removed.append(p.name)
        except Exception:
            pass
    return {"ok": True, "name": final.name, "bytes": final.stat().st_size,
            "removed": removed}


def usage(data_dir) -> dict:
    """백업 폴더가 지금 얼마나 쓰고 있나. 디스크 여유도 같이."""
    out_dir = backups_dir(data_dir)
    n, b = 0, 0
    for p in out_dir.iterdir():
        if p.is_file():
            n += 1
            b += p.stat().st_size
    try:
        st = shutil.disk_usage(str(data_dir))
        disk = {"total": st.total, "used": st.used, "free": st.free}
    except Exception:
        disk = {}
    return {"count": n, "bytes": b, "disk": disk}
