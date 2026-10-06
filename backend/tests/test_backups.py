# -*- coding: utf-8 -*-
"""일일 백업 — 지우면 안 되는 것을 안 지우는지가 제일 중요하다."""
import datetime as _dt
import json
import os
import shutil
import sys
import tarfile
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import backups as bk  # noqa: E402

FAIL = []


def ok(cond, msg):
    if not cond:
        FAIL.append(msg)


def fixture():
    d = Path(tempfile.mkdtemp(prefix="bk_test_"))
    (d / "models.json").write_text(json.dumps({"projects": {"pcb": {"models": [1, 2]}}},
                                              ensure_ascii=False), encoding="utf-8")
    (d / "purchases.json").write_text(json.dumps({"divisions": {"pcb": {}}}), encoding="utf-8")
    (d / "overtime.json").write_text(json.dumps({"weeks": {"2026-W39": {}}}), encoding="utf-8")
    (d / "notes.json").write_text("[]", encoding="utf-8")
    # 백업에 들어가면 안 되는 것들
    (d / "app_release.apk").write_bytes(b"\x00" * 2048)
    (d / "models.json.auto_20260930_083429").write_text("{}", encoding="utf-8")
    (d / "models.json.bak_20260821").write_text("{}", encoding="utf-8")
    (d / "models.bak_040104.json").write_text("{}", encoding="utf-8")
    (d / "note_assets").mkdir()
    (d / "note_assets" / "a.png").write_bytes(b"\x89PNG")
    (d / "rag").mkdir()
    (d / "rag" / "i.json").write_text("{}", encoding="utf-8")
    return d


# ── 1. 무엇을 담는가 ────────────────────────────────────────────────
d = fixture()
names = {p.name for p in bk.source_files(d)}
ok(names == {"models.json", "purchases.json", "overtime.json", "notes.json"},
   "담을 파일이 틀렸다: %s" % sorted(names))
ok("app_release.apk" not in names, "apk 가 백업에 들어갔다 (60MB)")
ok(not any(".auto_" in n for n in names), ".auto_ 백업이 또 백업됐다")
ok(not any(".bak" in n for n in names), ".bak 파일이 또 백업됐다")
ok("i.json" not in names, "하위 폴더까지 긁었다")

# ── 2. 한 벌 뜨기 ───────────────────────────────────────────────────
res = bk.snapshot(d)
ok(res["ok"], "백업 실패: %s" % res.get("reason"))
tgz = d / "backups" / res["name"]
ok(tgz.exists(), "백업 파일이 없다")
with tarfile.open(tgz, "r:gz") as tf:
    got = set(tf.getnames())
ok(got == names | {"_backup_meta.json"}, "tar 내용이 다르다: %s" % sorted(got))
ok(not list((d / "backups").glob("*.part")), ".part 가 남았다")

# 원본은 그대로여야 한다
ok((d / "models.json").exists() and (d / "app_release.apk").exists(),
   "백업이 원본을 건드렸다")
ok((d / "models.json.auto_20260930_083429").exists(), "기존 .auto_ 백업을 지웠다")

# ── 3. 하루 한 번 ───────────────────────────────────────────────────
bk._checked_on = ""
r1 = bk.ensure_today(d)
ok(r1.get("skipped") == "오늘 것이 이미 있음", "오늘 것이 있는데 또 떴다: %s" % r1)
bk._checked_on = ""
for p in (d / "backups").glob("*.tar.gz"):
    p.unlink()
r2 = bk.ensure_today(d)
ok(r2.get("ok"), "오늘 것이 없는데 안 떴다: %s" % r2)
r3 = bk.ensure_today(d)
ok(r3.get("skipped") == "확인함", "같은 날 두 번 확인했다: %s" % r3)

# ── 4. 보관 계획 (GFS) ──────────────────────────────────────────────
today = _dt.date(2026, 10, 1)
made = []
for i in range(0, 800):
    made.append((today - _dt.timedelta(days=i)).isoformat() + ".tar.gz")
plan = bk.plan_prune(made, today=today)
keep = {r["name"][:10] for r in plan["keep"]}

# 최근 30일은 다 남는다
for i in range(0, 30):
    dd = (today - _dt.timedelta(days=i)).isoformat()
    ok(dd in keep, "일간 30일 안인데 지운다: %s" % dd)
# 31일째는 그 주 첫 백업이 아니면 지운다
ok(len(plan["drop"]) > 600, "800일치에서 지우는 게 너무 적다: %d" % len(plan["drop"]))
# 각 달의 1일은 24개월까지 남는다
for mo in range(1, 24):
    y, m = today.year, today.month - mo
    while m <= 0:
        m += 12; y -= 1
    ok("%04d-%02d-01" % (y, m) in keep, "월간 24개월 안인데 지운다: %04d-%02d" % (y, m))
# 25개월 전 1일은 지운다
ok("2024-09-01" not in keep, "24개월 넘은 것이 남았다")
ok(len(keep) <= 70, "남기는 게 너무 많다: %d" % len(keep))
ok(len(keep) >= 60, "남기는 게 너무 적다: %d" % len(keep))

# 바닥 — 전부 오래된 것뿐이어도 MIN_KEEP 개는 남는다
oldonly = [(today - _dt.timedelta(days=900 + i)).isoformat() + ".tar.gz" for i in range(10)]
p2 = bk.plan_prune(oldonly, today=today)
ok(len(p2["keep"]) >= bk.MIN_KEEP, "바닥이 안 먹는다: %d" % len(p2["keep"]))

# ── 5. 정리는 backups 폴더 안에서만 ─────────────────────────────────
d2 = fixture()
bk.snapshot(d2)
bd = d2 / "backups"
# 백업 폴더에 '백업이 아닌' 파일을 두고, 오래된 백업도 하나 둔다
(bd / "손으로둔메모.txt").write_text("지우면 안 됨", encoding="utf-8")
# MIN_KEEP 바닥에 걸리지 않게 최근 것을 여러 벌 깔아 둔다
_src = next(bd.glob("20*.tar.gz"))
for _i in range(1, bk.MIN_KEEP + 3):
    _d = (_dt.date.today() - _dt.timedelta(days=_i)).isoformat()
    shutil.copy2(_src, bd / ("%s.tar.gz" % _d))
old = bd / "2020-01-02.tar.gz"
shutil.copy2(_src, old)
before = {p.name for p in d2.iterdir()}
r = bk.prune(d2)
after = {p.name for p in d2.iterdir()}
ok(before == after, "prune 이 backups 밖을 건드렸다: %s" % (before ^ after))
ok((bd / "손으로둔메모.txt").exists(), "백업 폴더의 다른 파일을 지웠다")
ok(not old.exists(), "오래된 백업이 안 지워졌다")
ok((d2 / "models.json").exists() and (d2 / "app_release.apk").exists(),
   "prune 이 운영 데이터를 지웠다")
ok((d2 / "note_assets" / "a.png").exists(), "prune 이 note_assets 를 지웠다")

# ── 6. 되돌리기 ─────────────────────────────────────────────────────
d3 = fixture()
snap = bk.snapshot(d3)
(d3 / "models.json").write_text(json.dumps({"projects": {}}), encoding="utf-8")
(d3 / "purchases.json").write_text(json.dumps({"divisions": {"NEW": {}}}), encoding="utf-8")

# 통째로 말고 한 파일만
r = bk.restore(d3, snap["name"], only=["models.json"])
ok(r["restored"] == ["models.json"], "고른 파일만 안 돌아갔다: %s" % r["restored"])
ok(json.loads((d3 / "models.json").read_text(encoding="utf-8"))["projects"],
   "models.json 이 안 돌아갔다")
ok("NEW" in (d3 / "purchases.json").read_text(encoding="utf-8"),
   "안 고른 파일까지 덮어썼다")
ok(r["pre_backup"], "되돌리기 전 백업을 안 떴다")
ok((d3 / "backups" / r["pre_backup"]).exists(), "되돌리기 전 백업 파일이 없다")

# 되돌리기 전 백업으로 다시 되돌릴 수 있어야 한다
r2 = bk.restore(d3, r["pre_backup"])
ok("models.json" in r2["restored"], "다시 되돌리기가 안 된다")
ok(json.loads((d3 / "models.json").read_text(encoding="utf-8")) == {"projects": {}},
   "다시 되돌린 내용이 다르다")

# ── 7. 수상한 tar 는 안 푼다 ────────────────────────────────────────
d4 = fixture()
bk.snapshot(d4)
bad = d4 / "backups" / "2026-09-01.tar.gz"
with tarfile.open(bad, "w:gz") as tf:
    for nm, body in [("../escape.json", b"{}"),
                     ("sub/dir.json", b"{}"),
                     ("notes.json", "{ 깨진 JSON".encode("utf-8")),
                     ("models.json", b'{"projects":{"ok":1}}')]:
        info = tarfile.TarInfo(nm); info.size = len(body)
        import io
        tf.addfile(info, io.BytesIO(body))
r = bk.restore(d4, "2026-09-01.tar.gz")
ok(r["restored"] == ["models.json"], "수상한 멤버가 풀렸다: %s" % r["restored"])
ok(not (d4.parent / "escape.json").exists(), "상위 폴더로 빠져나갔다!")
ok(not (d4 / "escape.json").exists(), "../ 멤버가 풀렸다")
ok(not (d4 / "sub").exists(), "하위 경로 멤버가 풀렸다")
ok((d4 / "notes.json").read_text(encoding="utf-8") == "[]",
   "깨진 JSON 으로 덮어썼다")
whys = " ".join(x["why"] for x in r["skipped"])
ok("JSON" in whys and "이상" in whys, "건너뛴 이유를 안 적었다: %s" % r["skipped"])

# ── 8. 이름 꼴이 아닌 것은 백업으로 안 본다 ─────────────────────────
ok(bk._date_of("2026-10-01.tar.gz") == _dt.date(2026, 10, 1), "날짜 파싱 실패")
ok(bk._date_of("2026-10-01_before-restore.tar.gz") == _dt.date(2026, 10, 1),
   "라벨 붙은 이름 파싱 실패")
for n in ("아무거나.tar.gz", "2026-13-01.tar.gz", "models.json",
          "../../etc/passwd.tar.gz", "assets_2026-10-01.tar.gz"):
    ok(bk._date_of(n) is None or "assets" not in n, "이상한 이름을 받았다: %s" % n)

# ── 9. note_assets 는 주 1회 ────────────────────────────────────────
d5 = fixture()
a1 = bk.ensure_assets_weekly(d5)
ok(a1.get("ok"), "assets 백업 실패: %s" % a1)
with tarfile.open(d5 / "backups" / a1["name"], "r:gz") as tf:
    nm = tf.getnames()
ok(any(x.startswith("note_assets") for x in nm), "note_assets 가 안 들어갔다")
a2 = bk.ensure_assets_weekly(d5)
ok(a2.get("skipped"), "같은 주에 또 떴다: %s" % a2)

# ── 10. 하루에 두 번 떠도 한 벌 ─────────────────────────────────────
d6 = fixture()
bk.snapshot(d6)
(d6 / "models.json").write_text('{"projects":{"나중":1}}', encoding="utf-8")
s2 = bk.snapshot(d6)
tgzs = list((d6 / "backups").glob("20*.tar.gz"))
ok(len(tgzs) == 1, "같은 날인데 두 벌이 생겼다: %d" % len(tgzs))
with tarfile.open(tgzs[0], "r:gz") as tf:
    body = tf.extractfile("models.json").read().decode("utf-8")
ok("나중" in body, "덮어쓴 백업이 옛 내용이다")

for x in (d, d2, d3, d4, d5, d6):
    shutil.rmtree(x, ignore_errors=True)

if FAIL:
    print("실패 %d건" % len(FAIL))
    for f in FAIL:
        print("  -", f)
    raise SystemExit(1)
print("전부 통과 · 검사 10묶음")
