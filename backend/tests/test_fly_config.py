# -*- coding: utf-8 -*-
"""배포 설정 — 한 파일만, 루트에서.

fly.toml 이 두 개였던 적이 있다. 루트와 backend/ 에 하나씩. 설정은 backend
쪽이 더 자세했는데, 그 폴더에서는 빌드가 아예 안 된다 — backend/Dockerfile 이
`COPY backend/requirements.txt` 를 하니 빌드 기준 폴더가 저장소 루트여야 한다.

더 나쁜 건 루트 쪽에 DATA_DIR 이 없었다는 것이다. 그게 빠지면 데이터가
/data 볼륨이 아니라 컨테이너 안에 쓰여서 다음 배포 때 통째로 사라진다.
(실제 운영은 fly secrets 에 DATA_DIR 이 들어 있어 무사했다.)

여기서 지키는 것
  · fly.toml 은 루트에 하나뿐이다
  · 루트 fly.toml 이 backend/Dockerfile 을 가리킨다
  · Dockerfile 의 COPY 가 루트 기준이라는 사실과 어긋나지 않는다
  · https 전용이면 관리자 쿠키에 Secure 를 건다
"""
import sys
from pathlib import Path

BACK = Path(__file__).resolve().parent.parent
ROOT = BACK.parent
sys.path.insert(0, str(BACK))

try:
    import tomllib
except ModuleNotFoundError:          # 3.10 이하
    tomllib = None

FAIL = []


def ok(c, m):
    if not c:
        FAIL.append(m)


# ── 1. fly.toml 은 하나뿐이다 ───────────────────────────────────────
found = sorted(p.relative_to(ROOT).as_posix()
               for p in ROOT.rglob("fly.toml")
               if ".git" not in p.parts and "venv" not in p.parts
               and "node_modules" not in p.parts)
ok(found == ["fly.toml"],
   "fly.toml 이 하나(루트)여야 한다. 지금: %s\n"
   "    둘이 있으면 어느 것으로 배포했는지 알 수 없고, 설정이 갈린다." % found)

FLY = ROOT / "fly.toml"
ok(FLY.exists(), "루트에 fly.toml 이 없다")
raw = FLY.read_text(encoding="utf-8") if FLY.exists() else ""


# ── 2. 빌드 기준 폴더가 Dockerfile 과 맞는가 ────────────────────────
DF = (BACK / "Dockerfile").read_text(encoding="utf-8")
root_based = [ln.strip() for ln in DF.splitlines()
              if ln.strip().startswith("COPY ")
              and ("backend/" in ln or "CHANGELOG.md" in ln)]
ok(root_based,
   "Dockerfile 에 루트 기준 COPY 가 없다 — 이 테스트의 전제가 바뀌었다")

if tomllib and raw:
    cfg = tomllib.loads(raw)
    ok(cfg.get("build", {}).get("dockerfile") == "backend/Dockerfile",
       "루트 fly.toml 이 backend/Dockerfile 을 가리켜야 한다: %r"
       % cfg.get("build"))
    ok(cfg.get("app") == "project-summary-mkoo",
       "앱 이름이 다르다: %r" % cfg.get("app"))

    mounts = cfg.get("mounts")
    if isinstance(mounts, list):
        mounts = mounts[0] if mounts else {}
    ok((mounts or {}).get("destination") == "/data",
       "볼륨이 /data 에 붙어야 한다: %r" % mounts)

    env = cfg.get("env") or {}
    ok(str(env.get("PORT")) == "8080", "PORT 가 8080 이어야 한다: %r" % env.get("PORT"))
    ok(str(env.get("ADMIN_COOKIE_SECURE", "")).lower() == "true",
       "force_https 로 돌리면서 관리자 쿠키에 Secure 를 안 걸고 있다")

    http = cfg.get("http_service") or {}
    ok(http.get("force_https") is True, "force_https 가 켜져 있어야 한다")
    ok(http.get("internal_port") == 8080,
       "internal_port 가 Dockerfile 의 8080 과 달라진다: %r"
       % http.get("internal_port"))


# ── 3. DATA_DIR 은 비밀값으로 넣는다 (파일에 적지 않는다) ───────────
#
# 적어 두면 두 군데가 생기고, 시크릿이 이기기 때문에 파일만 고치고
# '왜 안 바뀌지' 하게 된다. 대신 어디 있는지는 주석으로 남긴다.
ok("DATA_DIR" in raw,
   "fly.toml 에 DATA_DIR 이야기가 한 줄도 없다 — "
   "빠지면 데이터가 날아가는 설정이라 어디 있는지는 적어 둬야 한다")
ok("secrets" in raw or "시크릿" in raw or "비밀값" in raw,
   "비밀값을 어디에 넣는지 적혀 있지 않다")


# ── 4. 배포 위치가 적혀 있는가 ──────────────────────────────────────
ok("루트" in raw and "deploy" in raw,
   "어느 폴더에서 배포하는지 fly.toml 에 적어 두세요 — 문서가 따로 없으면 "
   "다음 사람이 backend/ 에서 돌리다 시간을 버립니다")


if FAIL:
    print("실패 %d건" % len(FAIL))
    for f in FAIL:
        print("  -", f)
    raise SystemExit(1)
print("전부 통과 · 검사 4묶음 · fly.toml %d개" % len(found))
