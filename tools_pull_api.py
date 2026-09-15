"""공개 API 로 운영 데이터 스냅샷을 받는다 (관리자 로그인 없이 되는 범위).

  python3 tools_pull_api.py [받을_폴더]

models.json 원본이 아니라 '지금 화면에 보이는 값'의 사본이다. 그대로 되돌릴
수는 없지만, 무엇이 언제 사라졌는지 비교하고 손으로 되살릴 근거는 된다.
원본 통째로는 backup.sh 의 flyctl 쪽이 받는다.
"""
import datetime, json, os, shutil, ssl, subprocess, sys, urllib.error, urllib.request

BASE = os.getenv("ONEVIEW_URL", "https://project-summary-mkoo.fly.dev")
# daily-board 는 블룸 일 보고 자료다. 여기 빠져 있어서 제일 새 데이터가
# 백업에 안 들어가고 있었다.
PER_PROJECT = ("models", "models/detail", "weekly-board", "board-rows",
               "weekly-plan", "daily-board")

# macOS 에 딸려오는 python 은 인증서 묶음이 없어서 https 를 그냥 못 연다
# (CERTIFICATE_VERIFY_FAILED). certifi 가 있으면 그걸 쓰고, 없으면 시스템
# 신뢰 저장소를 쓰는 curl 로 넘어간다.
try:
    import certifi
    _CTX = ssl.create_default_context(cafile=certifi.where())
except Exception:
    _CTX = None

_use_curl = False


def _fetch(path):
    global _use_curl
    url = BASE + path
    if not _use_curl:
        try:
            with urllib.request.urlopen(url, timeout=40, context=_CTX) as r:
                return r.read().decode("utf-8")
        except (ssl.SSLError, urllib.error.URLError) as e:
            if "CERTIFICATE" not in str(e).upper() and not isinstance(
                    getattr(e, "reason", None), ssl.SSLError):
                raise
            if not shutil.which("curl"):
                raise
            print("    (인증서 검증 실패 — curl 로 받습니다)")
            _use_curl = True
    r = subprocess.run(["curl", "-sS", "--max-time", "40", url],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"curl 실패: {r.stderr.strip()[:200]}")
    return r.stdout


def get(path):
    try:
        return json.loads(_fetch(path))
    except Exception as e:
        return {"_error": f"{type(e).__name__}: {e}"}


def main(outdir):
    os.makedirs(outdir, exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")

    index = get("/projects")
    keys = [p.get("key") for p in (index.get("projects") or []) if p.get("key")]
    if not keys:
        print(f"프로젝트 목록을 못 받았습니다: {str(index)[:200]}")
        return 1

    out = {
        "pulled_at": datetime.datetime.now().isoformat(timespec="seconds"),
        "source": BASE,
        "via": "공개 API (관리자 인증 없이 받을 수 있는 범위)",
        "projects_index": index,
        "divisions": {"automotive_summary": get("/divisions/automotive/summary")},
        "progress_summary": get("/projects-progress-summary"),
        "projects": {},
    }
    # 모델이 없는 프로젝트까지 여섯 번씩 두드리면 300번이 넘어 오래 걸린다.
    # 빈 프로젝트는 가벼운 것만 받아둔다.
    _has = {p.get("key") for p in (index.get("projects") or []) if p.get("has_models")}
    for k in keys:
        _paths = PER_PROJECT if k in _has else ("models", "daily-board")
        out["projects"][k] = {p.replace("/", "_").replace("-", "_"): get(f"/projects/{k}/{p}")
                              for p in _paths}

    errs = [f"{k}/{s}" for k in keys for s, v in out["projects"][k].items()
            if isinstance(v, dict) and v.get("_error")]
    if errs:
        print(f"못 받은 항목 {len(errs)}개: {', '.join(errs[:8])}")
        if len(errs) >= len(keys):      # 전부 실패면 저장하지 않는다
            print("전부 실패라 저장하지 않습니다.")
            return 1

    path = os.path.join(outdir, f"api_{stamp}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)

    lines, tm, tw, tp = [], 0, 0, 0
    for k in keys:
        models = []
        for _, v in ((out["projects"][k]["models"] or {}).get("groups") or {}).items():
            models += v.get("models") or []
        weeks = sum(len(wk or {}) for m in models
                    for wk in (m.get("weekly_plan") or {}).values())
        proc = sum(1 for m in models if m.get("process"))
        note = sum(1 for m in models if str(m.get("note") or "").strip())
        tm += len(models); tw += weeks; tp += proc
        if models:
            lines.append(f"{k:<26} 모델 {len(models):>4}  주차 {weeks:>5}  "
                         f"공정 {proc:>4}  메모 {note:>4}")
    lines.append(f"{'합계':<24} 모델 {tm:>4}  주차 {tw:>5}  공정 {tp:>4}")
    body = "\n".join(lines)
    with open(os.path.join(outdir, f"api_{stamp}.shape"), "w", encoding="utf-8") as f:
        f.write(body + "\n")
    print(body)
    print(f"\n{os.path.getsize(path):,} 바이트  ->  {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "backups"))
