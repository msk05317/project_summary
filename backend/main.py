"""
사업부 진행현황 보고 - 백엔드 메인
- PPT 업로드 → 슬라이드 PNG 변환 → GPT-4o 요약 → 신호등 분류
- 사용자 직접 차트/사진 업로드 및 부서·섹션 매핑
- 프로젝트별 상세 API 제공
"""
import os
import base64
import time
import secrets
import hmac
import json
import re
import shutil
import hashlib
import subprocess
from datetime import datetime, timedelta
from pathlib import Path

from fastapi import FastAPI, UploadFile, File, Form, HTTPException, Request, Response, Cookie, Depends
from typing import Optional
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import JSONResponse, HTMLResponse, RedirectResponse
from dotenv import load_dotenv
from openai import OpenAI
from rag import vector_store as _vs

from project_templates import (
    PROJECT_LABELS,
    aggregate_projects,
    build_project_detail,
)

# ============================================================
# config_loader 기반 분류 enrichment
# - 기존 응답 필드는 절대 변경하지 않는다.
# - division/project 정보는 "추가만" 한다.
# - 분류 실패해도 응답이 깨지지 않게 안전 처리한다.
# ============================================================
import config_loader as _cl


def _safe_text_for_card(card: dict) -> str:
    """카드 텍스트 분류에 사용할 문자열 합치기."""
    parts = [
        card.get("product") or "",
        card.get("headline") or "",
        card.get("project_key") or "",
    ]
    return " ".join([p for p in parts if p]).strip()




# ============================================================
# Dashboard cards 그룹핑 (모델 단위)
# - 같은 project_id + 동일/포함 모델명 → 한 카드
# - 그 안에 이슈(headline) 리스트
# ============================================================
def _normalize_model_name(name: str) -> str:
    """모델명에서 앞 번호 prefix 제거 + 공백 정리"""
    if not isinstance(name, str):
        return ""
    import re as _re
    t = name.strip()
    t = _re.sub(r"^\s*\d+(?:[-.]\d+)*[.)\]]?\s+", "", t)
    t = _re.sub(r"\s+", " ", t)
    return t.strip()

def _model_match_key(name: str, project_id, existing) -> str:
    """
    하이브리드 매칭:
    - 같은 project_id 안에서만 그룹핑
    - 정규화된 이름이 기존 어떤 키의 prefix 거나 그 반대면 같은 모델로 합침
    - existing 형식: {(project_id, key): ...}
    """
    base = _normalize_model_name(name).lower()
    if not base:
        return base
    for (pid, k) in existing:
        if pid != project_id:
            continue
        if not k:
            continue
        a, b = (base, k) if len(base) >= len(k) else (k, base)
        if a == b:
            return k
        if a.startswith(b):
            rest = a[len(b):]
            if rest[:1] in (" ", "(", "[", "{", "-", "_", ".", ",", ":", "/"):
                return k
    return base

_STATUS_SEVERITY = {"RED": 3, "BLUE": 2, "BLACK": 1}

def _worst_status(statuses):
    best = "BLACK"
    best_sev = -1
    for s in statuses:
        sev = _STATUS_SEVERITY.get(s, 0)
        if sev > best_sev:
            best_sev = sev
            best = s
    return best



# ---------- headline AI 요약 (캐시 기반) ----------
import hashlib as _hashlib_hl
import json as _json_hl
from pathlib import Path as _Path_hl

_HEADLINE_CACHE_PATH = _Path_hl(__file__).parent / "headline_cache.json"

def _load_headline_cache() -> dict:
    try:
        return _json_hl.loads(_HEADLINE_CACHE_PATH.read_text(encoding="utf-8"))
    except Exception:
        return {}

def _save_headline_cache(cache: dict) -> None:
    try:
        _HEADLINE_CACHE_PATH.write_text(
            _json_hl.dumps(cache, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
    except Exception:
        pass

def _pick_headline_source(dated_items: list, due_date_min) -> str:
    """
    dated_items: [(due_date, text, raw_str), ...]
    due_date_min 과 같은 날짜의 항목을 우선 선택.
    없으면 첫 항목.
    """
    if not dated_items:
        return ""
    if due_date_min:
        for d, t, _ in dated_items:
            if d == due_date_min:
                return t
    return dated_items[0][1]

def _ai_headline(source_text: str) -> str:
    """
    원문 한 줄을 15자 이내 행동 중심 요약으로 변환.
    캐시 우선. OpenAI 실패 시 원문 앞 15자.
    """
    src = (source_text or "").strip()
    if not src:
        return ""
    # 캐시 키: 원문 해시
    key = _hashlib_hl.sha256(src.encode("utf-8")).hexdigest()[:16]
    cache = _load_headline_cache()
    if key in cache:
        return cache[key]

    # OpenAI 호출
    result = ""
    try:
        if client is not None:
            prompt = (
                "다음 프로젝트 상태 문장에서 가장 중요한 액션 하나만 뽑아 20자 이내 명사형 한 줄로 요약해라. "
                "규칙: 원문을 앞에서부터 그대로 자르지 말고 핵심 행동/상태를 재구성. "
                "조사·어미·부사어 삭제. 여러 항목 나열 금지(가장 시급한 것 하나만). "
                "괄호·날짜·이모지 제거. 숫자와 모델명(W25, CEFEM 등)은 유지. "
                "예시: 'W23 24EA, W24 7개 완료, W25 3개 출하예정 (자재부족)' → 'W25 3개 출하 지연'. "
                "예시: 'CEFEM 2대, VTM 2대 제작중, VTM 1대 자재 지연' → 'VTM 1대 자재 지연'. "
                "요약문만 출력.\n\n"
                f"원문: {src}"
            )
            resp = client.chat.completions.create(
                model="gpt-4o-mini",
                messages=[{"role": "user", "content": prompt}],
                temperature=0.2,
                max_tokens=40,
            )
            result = (resp.choices[0].message.content or "").strip()
            # 따옴표/쌍따옴표 감싸져 오면 제거
            result = result.strip("\"'` ")
            # 개행 제거
            result = result.split("\n")[0].strip()
    except Exception:
        result = ""

    # 폴백: 원문 앞 15자
    if not result:
        result = src[:22]

    # 15자 초과 방어
    if len(result) > 24:
        result = result[:24].rstrip() + "…"

    cache[key] = result
    _save_headline_cache(cache)
    return result

def _normalize_issue_headline(text: str) -> str:
    """
    이슈 헤드라인 dedup 용 정규화 (중간 강도).
    - 앞쪽 번호 prefix 제거
    - 양 끝 공백/구두점 정리
    - 다중 공백 1개로
    - 끝쪽의 보조어 (중/진행/예정/완료/중임/중입니다 등) 제거
    - 한글/영문 모델명 사이 공백 통일
    - 비교용이므로 lowercase
    """
    if not isinstance(text, str):
        return ""
    import re as _re
    t = text.strip()
    # 앞 번호 prefix
    t = _re.sub(r"^\s*\d+(?:[-.]\d+)*[.)\]]?\s+", "", t)
    # 끝쪽 보조어 반복 제거
    suffixes = [
        "중입니다", "입니다", "중임", "되었음", "되었습니다",
        "중", "진행 중", "진행중", "진행", "예정", "완료", "완료됨",
        "진행 예정", "수행 중", "검토 중", "검토중",
    ]
    changed = True
    while changed:
        changed = False
        for suf in suffixes:
            if t.lower().endswith(suf.lower()):
                t = t[: -len(suf)].rstrip(" ,.;:·-")
                changed = True
    # 다중 공백/구두점 정리
    t = _re.sub(r"\s+", " ", t)
    t = t.strip(" ,.·-;:")
    return t.lower()

def _group_dashboard_cards(cards: list) -> list:
    """
    cards 를 모델 단위로 그룹핑.
    """
    groups = {}            # key=(project_id, model_key) → group dict
    order = []             # 그룹 등장 순서 보존
    issue_seen = {}        # 그룹 내 (status, headline) 중복 제거용

    for c in cards:
        product = c.get("product") or ""
        pid = c.get("project_id")  # None 가능 (미분류)
        # 미분류는 project_id 대신 라벨 "__unclassified__" 로 강제
        bucket_pid = pid if pid else "__unclassified__"

        match_key = _model_match_key(product, bucket_pid, groups.keys())
        gkey = (bucket_pid, match_key)

        if gkey not in groups:
            groups[gkey] = {
                "model": _normalize_model_name(product) or product,
                "status": c.get("status") or "BLACK",
                "project_id": pid,
                "project_label": c.get("project_label"),
                "project_badge": c.get("project_badge"),
                "division_id": c.get("division_id"),
                "division_label": c.get("division_label"),
                "report_date": c.get("report_date"),
                "report_family": c.get("report_family"),
                "issues": [],
                "_statuses": [],
            }
            order.append(gkey)
            issue_seen[gkey] = set()
        else:
            # 더 짧은(=상위) 모델명이 나중에 들어오면 그걸로 표시 보정 (예: "챔버 13종" 보다 "챔버" 우선)
            existing_name = groups[gkey]["model"]
            new_name = _normalize_model_name(product) or product
            if len(new_name) < len(existing_name):
                groups[gkey]["model"] = new_name

        # 이슈 dedup (정규화 헤드라인 기반)
        st = c.get("status") or "BLACK"
        head = (c.get("headline") or "").strip()
        # summary_bullets / due_date_min 은 headline 없어도 통과
        sb = c.get("summary_bullets") or []
        if sb and not groups[gkey].get("summary_bullets"):
            groups[gkey]["summary_bullets"] = sb
        ddm = c.get("due_date_min")
        if ddm and not groups[gkey].get("due_date_min"):
            groups[gkey]["due_date_min"] = ddm
        if st and st not in groups[gkey].get("_statuses", []):
            groups[gkey]["_statuses"].append(st)
        if not head:
            continue
        norm = _normalize_issue_headline(head)
        sig = (st, norm) if norm else (st, head.lower())
        if sig in issue_seen[gkey]:
            # 더 길고 풍부한 표현이 들어오면 표시용 headline 만 갱신
            for it in groups[gkey]["issues"]:
                if it.get("status") == st and _normalize_issue_headline(it.get("headline", "")) == norm:
                    if len(head) > len(it.get("headline", "")):
                        it["headline"] = head
                    break
            continue
        issue_seen[gkey].add(sig)
        groups[gkey]["issues"].append({
            "status": st,
            "headline": head,
            "doc_id": c.get("doc_id", ""),
        })
        # summary_bullets / due_date_min 통과
        sb = c.get("summary_bullets") or []
        if sb and not groups[gkey].get("summary_bullets"):
            groups[gkey]["summary_bullets"] = sb
        ddm = c.get("due_date_min")
        if ddm and not groups[gkey].get("due_date_min"):
            groups[gkey]["due_date_min"] = ddm
        groups[gkey]["_statuses"].append(st)

        # report_date 는 가장 최신으로 갱신
        rd_new = c.get("report_date") or ""
        rd_old = groups[gkey].get("report_date") or ""
        if rd_new > rd_old:
            groups[gkey]["report_date"] = rd_new

    result = []
    for gkey in order:
        g = groups[gkey]
        g["status"] = _worst_status(g.pop("_statuses") or [g["status"]])
        result.append(g)

    # 가장 심각한 그룹부터 정렬
    result.sort(key=lambda g: -_STATUS_SEVERITY.get(g["status"], 0))
    return result


def enrich_card(card: dict) -> dict:
    """
    /dashboard 카드에 division/project 분류 정보를 '추가'한다.
    기존 필드는 절대 건드리지 않는다.
    실패 시 새 필드는 None으로만 들어가고, 카드 자체는 정상 반환한다.
    """
    try:
        text = _safe_text_for_card(card)

        # 1순위: 백엔드가 이미 정한 project_key 가 있으면 그걸 신뢰
        hint_pid = card.get("project_key")
        project_id = None
        if hint_pid:
            # project_key 가 config 의 project_id 와 일치하는 경우 우선 사용
            if _cl.get_project(hint_pid):
                project_id = hint_pid

        # 2순위: config_loader 분류기
        if not project_id:
            project_id = _cl.classify_project(text)

        # 3순위: /upload 때 사장님이 지정한 폴백 (자동 분류가 다 실패한 경우)
        if not project_id:
            project_id = card.get("_fallback_project_id")

        division_id = _cl.derive_division_from_project(project_id)
        # 폴백 division 도 받기 (project_id 가 없는 극단적 경우)
        if not division_id:
            division_id = card.get("_fallback_division_id")

        project = _cl.get_project(project_id) if project_id else None
        division = _cl.get_division(division_id) if division_id else None

        # ⚠️ 기존 필드 그대로 두고 새 필드만 추가
        card["division_id"] = division_id
        card["division_label"] = division.get("label") if division else None
        card["project_id"] = project_id
        card["project_label"] = project.get("label") if project else None
        card["project_badge"] = _cl.badge_label_for_project(project_id)
    except Exception as e:
        # 어떤 이유로든 분류 실패해도 응답이 깨지지 않게
        card.setdefault("division_id", None)
        card.setdefault("division_label", None)
        card.setdefault("project_id", None)
        card.setdefault("project_label", None)
        card.setdefault("project_badge", None)
        card["_enrich_error"] = str(e)
    return card


def enrich_project_entry(entry: dict) -> dict:
    """
    /projects 응답 각 항목에 division/project 분류 정보를 '추가'한다.
    """
    try:
        # /projects 항목은 보통 project_key 또는 name/label 을 가짐
        hint_pid = entry.get("project_key") or entry.get("key")
        text = " ".join([
            str(entry.get("label") or ""),
            str(entry.get("name") or ""),
            str(hint_pid or ""),
        ]).strip()

        project_id = None
        if hint_pid and _cl.get_project(hint_pid):
            project_id = hint_pid
        if not project_id:
            project_id = _cl.classify_project(text)

        division_id = _cl.derive_division_from_project(project_id)
        project = _cl.get_project(project_id) if project_id else None
        division = _cl.get_division(division_id) if division_id else None

        entry["division_id"] = division_id
        entry["division_label"] = division.get("label") if division else None
        entry["project_id"] = project_id
        entry["project_label"] = project.get("label") if project else None
        entry["project_badge"] = _cl.badge_label_for_project(project_id)
    except Exception as e:
        entry.setdefault("division_id", None)
        entry.setdefault("division_label", None)
        entry.setdefault("project_id", None)
        entry.setdefault("project_label", None)
        entry.setdefault("project_badge", None)
        entry["_enrich_error"] = str(e)
    return entry


def enrich_project_detail(detail: dict) -> dict:
    """
    /projects/{key} 상세 응답 최상위에 분류 정보를 '추가'한다.
    """
    if not isinstance(detail, dict):
        return detail
    try:
        hint_pid = detail.get("project_key") or detail.get("key")
        text = " ".join([
            str(detail.get("label") or ""),
            str(detail.get("name") or ""),
            str(hint_pid or ""),
        ]).strip()

        project_id = None
        if hint_pid and _cl.get_project(hint_pid):
            project_id = hint_pid
        if not project_id:
            project_id = _cl.classify_project(text)

        division_id = _cl.derive_division_from_project(project_id)
        project = _cl.get_project(project_id) if project_id else None
        division = _cl.get_division(division_id) if division_id else None

        detail["division_id"] = division_id
        detail["division_label"] = division.get("label") if division else None
        detail["project_id"] = project_id
        detail["project_label"] = project.get("label") if project else None
        detail["project_badge"] = _cl.badge_label_for_project(project_id)
    except Exception as e:
        detail.setdefault("division_id", None)
        detail.setdefault("division_label", None)
        detail.setdefault("project_id", None)
        detail.setdefault("project_label", None)
        detail.setdefault("project_badge", None)
        detail["_enrich_error"] = str(e)
    return detail

from chart_extractor import extract_charts_from_pptx


# =========================================================
# 환경 변수
# =========================================================
load_dotenv()
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
UPLOAD_PASSWORD = os.getenv("UPLOAD_PASSWORD", "1234")
client = OpenAI(api_key=OPENAI_API_KEY) if OPENAI_API_KEY else None

BASE_DIR = Path(__file__).parent.resolve()

# Railway/프로덕션: /data (영구 Volume)
# 로컬 개발: backend 폴더 안
DATA_DIR = Path(os.getenv("DATA_DIR", str(BASE_DIR)))
DATA_DIR.mkdir(parents=True, exist_ok=True)

UPLOAD_DIR = DATA_DIR / "uploads"
UPLOAD_HASHES_PATH = DATA_DIR / "upload_hashes.json"
SLIDES_DIR = DATA_DIR / "slides"
SLIDE_IMAGES_DIR = DATA_DIR / "slide_images"   # 기존 호환용
CROPPED_DIR = DATA_DIR / "cropped"
LATEST_FILE = DATA_DIR / "reports_latest.json"
HISTORY_FILE = DATA_DIR / "reports_history.json"
# 주간 보고 첨부 자료 (표 JSON / 사진)
NOTE_ASSETS_DIR = DATA_DIR / "note_assets"
NOTE_TABLES_DIR = NOTE_ASSETS_DIR / "tables"
NOTE_PHOTOS_DIR = NOTE_ASSETS_DIR / "photos"

for d in [UPLOAD_DIR, SLIDES_DIR, SLIDE_IMAGES_DIR, CROPPED_DIR, NOTE_ASSETS_DIR, NOTE_TABLES_DIR, NOTE_PHOTOS_DIR]:
    d.mkdir(exist_ok=True)

# DATA_DIR이 git 경로와 다르면(Railway), git에 포함된 시드 자산을 영구 볼륨에 복사
try:
    import shutil
    seed_assets = BASE_DIR / "note_assets"
    if DATA_DIR != BASE_DIR and seed_assets.exists():
        for src in seed_assets.rglob("*"):
            if src.is_file():
                rel = src.relative_to(seed_assets)
                dst = NOTE_ASSETS_DIR / rel
                if not dst.exists():
                    dst.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(src, dst)
        print(f"[seed] note_assets seeded to {NOTE_ASSETS_DIR}")
except Exception as _e:
    print(f"[seed] note_assets seed failed: {_e}")

# notes.json 도 동일하게 시드
try:
    import shutil
    seed_notes = BASE_DIR / "notes.json"
    if DATA_DIR != BASE_DIR and seed_notes.exists() and not (DATA_DIR / "notes.json").exists():
        shutil.copy2(seed_notes, DATA_DIR / "notes.json")
        print(f"[seed] notes.json seeded to {DATA_DIR}")
except Exception as _e:
    print(f"[seed] notes.json seed failed: {_e}")

RETENTION_DAYS = 180


# =========================================================
# FastAPI 앱
# =========================================================
app = FastAPI(title="사업부 진행현황 보고 API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 정적 파일 마운트
app.mount("/slides", StaticFiles(directory=str(SLIDES_DIR)), name="slides")
app.mount("/slide_images", StaticFiles(directory=str(SLIDE_IMAGES_DIR)), name="slide_images")
app.mount("/cropped", StaticFiles(directory=str(CROPPED_DIR)), name="cropped")
app.mount("/note_photos", StaticFiles(directory=str(NOTE_PHOTOS_DIR)), name="note_photos")
_STATIC_DIR = BASE_DIR / "static"
_STATIC_DIR.mkdir(exist_ok=True)
app.mount("/static", StaticFiles(directory=str(_STATIC_DIR)), name="static")

# ============================================================
# 관리자 세션 (8시간)
# ============================================================
ADMIN_SESSION_COOKIE = "admin_auth"
ADMIN_SESSION_MAX_LIFETIME_SEC = int(os.getenv("ADMIN_SESSION_MAX_LIFETIME_SEC", str(24 * 3600)))  # 발급 후 최대 24시간
ADMIN_SESSION_TTL_SEC = 8 * 60 * 60
ADMIN_SESSION_SECRET = os.getenv("ADMIN_SESSION_SECRET", "")
ADMIN_COOKIE_SECURE = os.getenv("ADMIN_COOKIE_SECURE", "false").lower() == "true"
if not ADMIN_SESSION_SECRET:
    ADMIN_SESSION_SECRET = hashlib.sha256(("session::" + UPLOAD_PASSWORD).encode()).hexdigest()

def _b64u(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()

def _b64u_decode(s: str) -> bytes:
    pad = "=" * (-len(s) % 4)
    return base64.urlsafe_b64decode(s + pad)

def _sign_session(exp_ts: int, issued_at: int) -> str:
    msg = f"{issued_at}.{exp_ts}".encode()
    sig = hmac.new(ADMIN_SESSION_SECRET.encode(), msg, hashlib.sha256).digest()
    return f"{issued_at}.{exp_ts}.{_b64u(sig)}"

def _verify_session(token: Optional[str]) -> Optional[int]:
    if not token:
        return None
    try:
        parts = token.split(".")
        if len(parts) != 3:
            return None
        issued_str, exp_str, sig_b64 = parts
        issued_at = int(issued_str)
        exp_ts = int(exp_str)
        msg = f"{issued_at}.{exp_ts}".encode()
        expected = hmac.new(ADMIN_SESSION_SECRET.encode(), msg, hashlib.sha256).digest()
        provided = _b64u_decode(sig_b64)
        if not hmac.compare_digest(expected, provided):
            return None
        now = int(time.time())
        if exp_ts < now:
            return None
        # 발급 후 최대 수명 초과 검사
        if now - issued_at > ADMIN_SESSION_MAX_LIFETIME_SEC:
            return None
        return exp_ts
    except Exception:
        return None

def _issue_session_cookie(response: Response, issued_at: Optional[int] = None):
    now = int(time.time())
    if issued_at is None:
        issued_at = now  # 새 발급
    exp_ts = now + ADMIN_SESSION_TTL_SEC
    # 발급 후 최대 수명 초과 방지: exp_ts를 issued_at + max_lifetime 으로 제한
    hard_limit = issued_at + ADMIN_SESSION_MAX_LIFETIME_SEC
    if exp_ts > hard_limit:
        exp_ts = hard_limit
    token = _sign_session(exp_ts, issued_at)
    response.set_cookie(
        key=ADMIN_SESSION_COOKIE,
        value=token,
        max_age=max(0, exp_ts - now),
        httponly=True,
        samesite="lax",
        secure=ADMIN_COOKIE_SECURE,
        path="/",
    )
    return exp_ts

def get_admin_session(admin_auth: Optional[str] = Cookie(default=None)) -> int:
    exp = _verify_session(admin_auth)
    if not exp:
        raise HTTPException(status_code=401, detail="인증이 필요합니다.")
    return exp

_ADMIN_LOGIN_HTML = """<!doctype html>
<html lang=\"ko\"><head>
<meta charset=\"utf-8\" />
<title>관리자 인증</title>
<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\" />
<style>
  html, body { height:100%; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Pretendard', sans-serif; background:#f1f5f9; margin:0; min-height:100vh; display:flex; align-items:center; justify-content:center; padding: 16px; box-sizing: border-box; }
  .card { background:#fff; padding:32px; border-radius:14px; box-shadow:0 8px 30px rgba(0,0,0,0.08); width:340px; margin: auto; }
  h2 { margin:0 0 8px; color:#1E3A5F; font-size:20px; }
  p { color:#64748b; font-size:13px; margin:0 0 18px; }
  input[type=password] { width:100%; padding:12px; font-size:14px; border:1px solid #cbd5e1; border-radius:8px; box-sizing:border-box; }
  button { width:100%; padding:12px; margin-top:14px; background:#1E3A5F; color:#fff; border:none; border-radius:8px; font-weight:700; font-size:14px; cursor:pointer; }
  .err { color:#b91c1c; font-size:13px; margin-top:10px; min-height:18px; }
</style></head>
<body>
  <form class="card" id="loginForm">
    <h2>🔒 관리자 인증</h2>
    <p>업로드 비밀번호를 입력하세요. 8시간 유지됩니다.</p>
    <input type=\"password\" id=\"pw\" placeholder=\"비밀번호\" required autofocus />
    <button type=\"submit\">로그인</button>
    <div class=\"err\" id=\"err\"></div>
  </form>
<script>
document.getElementById('loginForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const pw = document.getElementById('pw').value;
  const err = document.getElementById('err');
  err.textContent = '';
  try {
    const fd = new FormData();
    fd.append('password', pw);
    const r = await fetch('/admin/login', { method: 'POST', body: fd, credentials: 'same-origin' });
    if (r.ok) {
      const next = new URLSearchParams(location.search).get('next') || '/admin/upload';
      location.href = next;
    } else {
      const j = await r.json().catch(()=>({}));
      err.textContent = j.detail || '비밀번호가 올바르지 않습니다.';
    }
  } catch (e) {
    err.textContent = '네트워크 오류';
  }
});
</script>


</body></html>"""

@app.get("/admin/login", response_class=HTMLResponse)
def admin_login_page(admin_auth: Optional[str] = Cookie(default=None)):
    if _verify_session(admin_auth):
        return RedirectResponse(url="/admin/upload", status_code=302)
    return HTMLResponse(content=_ADMIN_LOGIN_HTML)

@app.post("/admin/login")
def admin_login_submit(response: Response, password: str = Form(...)):
    if password != UPLOAD_PASSWORD:
        raise HTTPException(status_code=401, detail="비밀번호가 올바르지 않습니다.")
    exp = _issue_session_cookie(response)
    return {"ok": True, "expires_at": exp}

@app.post("/admin/logout")
def admin_logout(response: Response):
    response.delete_cookie(ADMIN_SESSION_COOKIE, path="/")
    return {"ok": True}

@app.post("/admin/extend")
def admin_extend(
    response: Response,
    admin_auth: Optional[str] = Cookie(default=None),
    _exp: int = Depends(get_admin_session),
):
    # 기존 토큰의 issued_at 보존 → 최대 수명 24시간 강제
    issued_at = None
    if admin_auth:
        try:
            parts = admin_auth.split(".")
            if len(parts) == 3:
                issued_at = int(parts[0])
        except Exception:
            pass
    now = int(time.time())
    if issued_at is not None and now - issued_at >= ADMIN_SESSION_MAX_LIFETIME_SEC:
        raise HTTPException(status_code=401, detail="세션 최대 수명을 초과했습니다. 다시 로그인해 주세요.")
    exp = _issue_session_cookie(response, issued_at=issued_at)
    return {"ok": True, "expires_at": exp, "max_lifetime_remaining": (issued_at + ADMIN_SESSION_MAX_LIFETIME_SEC - now) if issued_at else ADMIN_SESSION_MAX_LIFETIME_SEC}

@app.get("/admin/session")
def admin_session_info(_exp: int = Depends(get_admin_session)):
    return {"ok": True, "expires_at": _exp, "ttl_sec": ADMIN_SESSION_TTL_SEC}



# =========================================================
# 유틸
# =========================================================
def _read_json(path: Path, default):
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def _write_json(path: Path, data):
    path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def _make_doc_id(filename: str) -> str:
    short = hashlib.md5(
        f"{filename}_{datetime.now().isoformat()}".encode("utf-8")
    ).hexdigest()[:12]
    return short


def _convert_pptx_to_png(pptx_path: Path, out_dir: Path):
    """LibreOffice + Poppler 로 PPTX → PDF → PNG 변환"""
    out_dir.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["soffice", "--headless", "--convert-to", "pdf",
         "--outdir", str(out_dir), str(pptx_path)],
        check=True, capture_output=True,
    )
    pdf_file = out_dir / (pptx_path.stem + ".pdf")
    if not pdf_file.exists():
        raise RuntimeError("PDF 변환 실패")
    subprocess.run(
        ["pdftoppm", "-png", "-r", "150",
         str(pdf_file), str(out_dir / "slide")],
        check=True, capture_output=True,
    )
    # slide-1.png → slide_01.png 정규화
    for p in sorted(out_dir.glob("slide-*.png")):
        num = int(p.stem.split("-")[-1])
        p.rename(out_dir / f"slide_{num:02d}.png")
    try:
        pdf_file.unlink()
    except Exception:
        pass


def _extract_text_per_slide(pptx_path: Path):
    """슬라이드별 텍스트 추출"""
    from pptx import Presentation
    prs = Presentation(str(pptx_path))
    texts = []
    for slide in prs.slides:
        buf = []
        for shape in slide.shapes:
            if shape.has_text_frame:
                buf.append(shape.text_frame.text)
            if shape.has_table:
                for row in shape.table.rows:
                    for cell in row.cells:
                        buf.append(cell.text)
        texts.append("\n".join(buf))
    return texts


def _extract_pptx_text_and_tables(pptx_path: Path):
    """슬라이드별 텍스트(표 제외)와 표를 분리 추출.
    반환: (slide_texts: list[str], slide_tables: list[list[dict]])
    각 표: {"headers": [...], "rows": [[...], ...]}
    """
    from pptx import Presentation
    prs = Presentation(str(pptx_path))
    slide_texts = []
    slide_tables = []
    for slide in prs.slides:
        text_buf = []
        tables_in_slide = []
        for shape in slide.shapes:
            if shape.has_text_frame:
                t = shape.text_frame.text
                if t and t.strip():
                    text_buf.append(t)
            if shape.has_table:
                tbl = shape.table
                rows_data = []
                for row in tbl.rows:
                    rows_data.append([cell.text.strip() for cell in row.cells])
                if rows_data:
                    headers = rows_data[0]
                    body = rows_data[1:] if len(rows_data) > 1 else []
                    tables_in_slide.append({"headers": headers, "rows": body})
        slide_texts.append("\n".join(text_buf))
        slide_tables.append(tables_in_slide)
    return slide_texts, slide_tables


def _classify_status_with_gpt(slide_texts: list[str]) -> dict:
    if not client:
        return {"products": []}

    joined = "\n\n".join([f"=== Slide {i+1} ===\n{t}" for i, t in enumerate(slide_texts)])

    system_prompt = """너는 반도체 사업부의 임원 보고서 분석 어시스턴트다.
PPT 슬라이드 텍스트를 읽고, 등장하는 모든 프로젝트/제품을 JSON으로 정리한다.

[가장 중요] 사장님이 30초 안에 다 파악할 수 있도록 정리한다.
- summary_bullets: 핵심 3줄 (한 줄 25자 이내, 가장 중요한 사실만)
- sections: 상세 내용 (펼쳤을 때 보임)

규칙:
1. 섹션 구조는 PPT 원문에 등장한 그대로 따른다 (양산/개발/EMA/주차별 출하/Dep챔버진행 등).
2. PPT에 없는 섹션은 만들지 말 것.
3. items는 원문을 가능하면 한 줄로 축약 (불필요한 수식어 제거, 핵심 숫자/일정 유지).
4. notes에는 ※ 또는 참고 사항만.
5. status:
   - RED: 출하 미달, PO 미접수, 자재 쇼티지, 일정 지연 등 즉시 확인
   - BLUE: 진행 중, 정상 추진
   - BLACK: 완료/이슈 없음
6. headline: 가장 중요한 한 줄 (15자 이내 권장).
7. summary_bullets: 핵심 3줄 (정확히 3개, 각 25자 이내).

JSON 스키마:
{
  "products": [
    {
      "name": "프로젝트명",
      "category": "분류",
      "status": "RED|BLUE|BLACK",
      "headline": "핵심 한 줄",
      "summary_bullets": ["요약1", "요약2", "요약3"],
      "header_summary": "상단 요약 (선택)",
      "sections": [
        {"title": "섹션 제목", "items": ["불릿1"], "notes": ["※ 참고"]}
      ]
    }
  ]
}"""

    try:
        resp = client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": f"다음 PPT 내용을 정리:\n\n{joined}"},
            ],
            response_format={"type": "json_object"},
            temperature=0.2,
        )
        return json.loads(resp.choices[0].message.content)
    except Exception as e:
        print(f"🔴 GPT 분류 실패: {e}")
        return {"products": []}

def _cleanup_old_files():
    """6개월 지난 파일 자동 삭제"""
    cutoff = datetime.now() - timedelta(days=RETENTION_DAYS)
    for base in [UPLOAD_DIR, SLIDES_DIR, SLIDE_IMAGES_DIR, CROPPED_DIR]:
        if not base.exists():
            continue
        for entry in base.iterdir():
            try:
                mtime = datetime.fromtimestamp(entry.stat().st_mtime)
                if mtime < cutoff:
                    if entry.is_dir():
                        shutil.rmtree(entry, ignore_errors=True)
                    else:
                        entry.unlink()
            except Exception:
                continue


def _update_latest(summary):
    """
    최신 보고서 저장.
    - 같은 doc_id가 있으면 갱신 (중복 방지)
    - 그 외에는 누적
    - report_family는 부가 정보로만 사용 (덮어쓰기 키로 사용 X)
    - 최대 50개까지만 유지 (오래된 것부터 제거)
    """
    latest = _read_json(LATEST_FILE, [])
    new_doc_id = summary.get("doc_id")

    # 같은 doc_id 있으면 제거하고 새로 추가
    latest = [r for r in latest if r.get("doc_id") != new_doc_id]
    latest.append(summary)

    # 업로드 시각 기준 최신순 정렬, 최대 50개
    latest.sort(
        key=lambda r: r.get("uploaded_at") or r.get("report_meta", {}).get("date", ""),
        reverse=True
    )
    latest = latest[:50]

    _write_json(LATEST_FILE, latest)

# =========================================================
# 1. 헬스체크
# =========================================================
@app.get("/health")
def health():
    return {"status": "ok", "time": datetime.now().isoformat()}


# =========================================================
# 2. PPT 업로드
# =========================================================


def _load_upload_hash_index():
    try:
        if not UPLOAD_HASHES_PATH.exists():
            return {}
        return json.loads(UPLOAD_HASHES_PATH.read_text(encoding="utf-8"))
    except Exception:
        return {}

def _save_upload_hash_index(data):
    try:
        UPLOAD_HASHES_PATH.write_text(
            json.dumps(data, ensure_ascii=False, indent=2),
            encoding="utf-8"
        )
    except Exception:
        pass

def _find_duplicate_upload_by_hash(file_hash: str):
    idx = _load_upload_hash_index()
    return idx.get(file_hash)

def _record_upload_hash(file_hash: str, saved_name: str, doc_id: str):
    idx = _load_upload_hash_index()
    idx[file_hash] = {
        "filename": saved_name,
        "doc_id": doc_id,
    }
    _save_upload_hash_index(idx)

@app.post("/upload")
async def upload_ppt(
    file: UploadFile = File(...),
    password: Optional[str] = Form(None),
    admin_auth: Optional[str] = Cookie(default=None),
    report_family: str = Form("default"),
    division_id: Optional[str] = Form(None),  # 5-2b: 사업부 사전 매핑 (선택)
    project_id: Optional[str] = Form(None),   # 5-2b: 프로젝트 사전 매핑 (선택)
    allow_duplicate: bool = Form(False),  # 중복 업로드 허용
):
    _has_session = bool(_verify_session(admin_auth))
    if not _has_session and password != UPLOAD_PASSWORD:
        raise HTTPException(status_code=401, detail="비밀번호가 틀립니다.")
    if not file.filename.lower().endswith((".pptx", ".ppt")):
        raise HTTPException(status_code=400, detail=".pptx 또는 .ppt 파일만 업로드 가능합니다.")

    # 파일 내용 읽기 + 해시 계산
    file_bytes = await file.read()
    file_hash = hashlib.sha256(file_bytes).hexdigest()

    # 중복 업로드 검사 (allow_duplicate 이 False 일 때만 차단)
    duplicate_hit = _find_duplicate_upload_by_hash(file_hash)
    if duplicate_hit and not allow_duplicate:
        return JSONResponse(
            status_code=409,
            content={
                "ok": False,
                "code": "duplicate_upload",
                "detail": "이미 업로드된 파일입니다. 같은 파일을 다시 올리려면 '중복 업로드 허용'을 체크하세요.",
                "duplicate_of": duplicate_hit.get("filename"),
            },
        )

    _cleanup_old_files()

    doc_id = _make_doc_id(file.filename)
    saved_pptx_path = UPLOAD_DIR / f"{doc_id}.pptx"
    saved_pptx_path.write_bytes(file_bytes)
    _record_upload_hash(file_hash, saved_pptx_path.name, doc_id)

    # slides/ 와 slide_images/ 둘 다 저장 (호환성)
    slides_out_dir = SLIDES_DIR / doc_id
    try:
        _convert_pptx_to_png(saved_pptx_path, slides_out_dir)
        # slide_images/ 에도 복사
        slide_images_out = SLIDE_IMAGES_DIR / doc_id
        if not slide_images_out.exists():
            shutil.copytree(slides_out_dir, slide_images_out)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"슬라이드 변환 실패: {e}")

    slide_texts = _extract_text_per_slide(saved_pptx_path)
    gpt_result = _classify_status_with_gpt(slide_texts)
    products = gpt_result.get("products", [])

    section_images = {}
    try:
        section_images = extract_charts_from_pptx(
            pptx_path=saved_pptx_path,
            slides_image_dir=slides_out_dir,
            output_dir=CROPPED_DIR,
            doc_id=doc_id,
        )
        print(f"🟢 차트 자동 추출 완료: {list(section_images.keys())}")
    except Exception as e:
        print(f"🔴 차트 자동 추출 실패: {e}")

    slide_images = {
        str(i + 1): f"/slides/{doc_id}/slide_{i+1:02d}.png"
        for i in range(len(slide_texts))
    }


    # ============================================================
    # 5-2b: 사장님이 사전 지정한 division_id/project_id 폴백 적용
    # - 자동 분류 성공 카드: 그대로 유지
    # - 자동 분류 실패 카드만 사장님 의도로 폴백
    # ============================================================
    if division_id or project_id:
        import config_loader as _cl
        try:
            _cl.reload()
        except Exception:
            pass
        for p in products:
            name = p.get("name") or p.get("product", "")
            category = p.get("category", "")
            text = f"{name} {category}".strip()
            try:
                auto_pid = _cl.classify_project(text)
            except Exception:
                auto_pid = None
            if not auto_pid:
                # 자동 분류 실패한 카드만 폴백
                if project_id:
                    p["_fallback_project_id"] = project_id
                if division_id:
                    p["_fallback_division_id"] = division_id

    summary = {
        "report_meta": {
            "report_family": report_family,
            "date": datetime.now().strftime("%Y-%m-%d"),
        },
        "doc_id": doc_id,
        "file_name": file.filename,
        "upload_timestamp": datetime.now().isoformat(),
        "products": products,
        "section_images": section_images,
        "slide_images": slide_images,
    }
    _update_latest(summary)

    return {
        "ok": True,
        "doc_id": doc_id,
        "product_count": len(products),
        "slide_count": len(slide_texts),
    }


# =========================================================
# 3. 대시보드 / 리포트
# =========================================================
def _due_status_one(due_raw: str) -> str:
    """단일 due_date 문자열 → 상태색."""
    from datetime import date
    due_raw = (due_raw or "").strip()
    if not due_raw:
        return "BLACK"  # 일정 없음 (내용은 있는데 일정 추출 안 됨)
    try:
        y, m, d = due_raw[:10].split("-")
        due = date(int(y), int(m), int(d))
    except Exception:
        return "BLACK"
    diff = (due - date.today()).days
    if diff < 0:
        return "RED"
    if diff <= 3:
        return "ORANGE"
    return "BLUE"


def _calc_card_status(card: dict) -> str:
    """카드 안 items 들의 due_date 들을 보고 가장 위험한 색으로 집계.
    빨강 > 주황 > 파랑 > 검정 순.
    items가 비어있거나 모두 due_date 없음 → BLACK."""
    priority = {"RED": 5, "ORANGE": 4, "BLUE": 3, "BLACK": 1}
    best = "BLACK"
    sections = card.get("sections") or []
    for sec in sections:
        for it in (sec.get("items") or []):
            if not isinstance(it, dict):
                continue
            s = _due_status_one(it.get("due_date") or "")
            if priority.get(s, 0) > priority.get(best, 0):
                best = s
                if best == "RED":
                    return best
    return best


@app.get("/dashboard")
def dashboard():
    """신호등 카드 - 각 카드에 project_key 포함 → Flutter에서 상세 이동에 사용"""
    from project_templates import _match_project_key  # 키워드 매핑 함수 재사용

    latest = _read_json(LATEST_FILE, [])
    cards = []
    for report in latest:
        report_date = (
            report.get("report_meta", {}).get("date")
            or report.get("report_date")
        )
        report_family = (
            report.get("report_meta", {}).get("report_family")
            or report.get("report_family", "")
        )
        for p in report.get("products", []):
            product_name = p.get("name") or p.get("product", "")
            category = p.get("category", "")
            # 프로젝트 키 매핑 (백엔드 로직 그대로)
            project_key = (
                _match_project_key(product_name)
                or _match_project_key(category)
                or _match_project_key(report_family)
            )
            cards.append({
                "doc_id": report.get("doc_id", ""),
                "product": product_name,
                "status": p.get("status", "BLACK"),
                "headline": p.get("headline", ""),
                "report_date": report_date,
                "report_family": report_family,
                "project_key": project_key,  # ← 추가
            })

    # 🟢 카드별로 division/project 분류 정보 enrichment (기존 필드 변경 없음)
    cards = [enrich_card(c) for c in cards]

    # 🟢 주간 보고 노트 카드도 대시보드에 포함
    # 같은 project_key 가 PPT/노트 양쪽에 있으면 노트 카드를 우선
    try:
        notes_data = _load_notes()
        notes_map = notes_data.get("notes", {}) or {}
        note_cards = []
        for div_id, div_notes in notes_map.items():
            report_date = (div_notes or {}).get("report_date", "") or ""
            for nc in (div_notes or {}).get("cards", []) or []:
                if not isinstance(nc, dict):
                    continue
                title = (nc.get("title") or "").strip()
                if not title:
                    continue
                # 카드 제목 → project_key 매칭
                pkey = (nc.get("project_key") or "").strip()
                if not pkey:
                    try:
                        pkey = _cl.classify_project(title) or ""
                    except Exception:
                        pkey = ""

                # headline / summary_bullets 추출
                headline = ""
                bullets = []
                from datetime import date as _date
                due_items = []        # (date, text, raw_str)
                dated_bullets = []    # 날짜 있는 항목만 (앱 카드 본문용)
                highlight_text = ""
                due_date_min = None
                for sec in (nc.get("sections") or []):
                    for it in (sec.get("items") or []):
                        if not isinstance(it, dict):
                            if isinstance(it, str) and len(bullets) < 3:
                                bullets.append(it)
                            continue
                        t = (it.get("type") or "bullet").lower()
                        txt = (it.get("text") or "").strip()
                        if not txt:
                            continue
                        if t == "highlight" and not highlight_text:
                            highlight_text = txt
                        d = (it.get("due_date") or "").strip()
                        if d:
                            try:
                                y, m, dd = d[:10].split("-")
                                due_d = _date(int(y), int(m), int(dd))
                                due_items.append((due_d, txt, d[:10]))
                                dated_bullets.append(f"{txt} ({d[5:10]})")
                                if due_date_min is None or due_d < due_date_min:
                                    due_date_min = due_d
                            except Exception:
                                pass
                        if t in ("bullet", "group_note", "sub") and len(bullets) < 5:
                            bullets.append(txt)

                # 카드 본문: 날짜 있는 항목만 표시. 일정 없으면 대시보드 제외
                if not dated_bullets:
                    continue
                bullets = dated_bullets[:10]

                # headline: summary_bullets[0] 또는 첫 dated bullet 에서 날짜 제거
                def _shorten(txt: str, limit: int = 20) -> str:
                    txt = (txt or "").strip()
                    if len(txt) <= limit:
                        return txt
                    return txt[:limit].rstrip() + "…"

                # headline: due_date_min 항목 우선 선택 후 AI 15자 요약
                headline_src = _pick_headline_source(due_items, due_date_min)
                headline = _ai_headline(headline_src) if headline_src else ""
                due_date_min_str = due_date_min.isoformat() if due_date_min else None

                computed_status = _calc_card_status(nc)
                note_cards.append({
                    "doc_id": f"note:{div_id}",
                    "product": title,
                    "status": computed_status,
                    "headline": headline,
                    "summary_bullets": bullets,
                    "due_date_min": due_date_min_str,
                    "report_date": report_date,
                    "report_family": "weekly_note",
                    "project_key": pkey or None,
                    "division_id": div_id,
                    "from_note": True,
                })

        # enrich (project_key 가 있으면 division/label 등 자동 채움)
        note_cards = [enrich_card(c) for c in note_cards]

        # 대시보드는 노트 카드만 표시 (PPT 카드는 관리자용 텍스트 추출 도구로만)
        cards = note_cards
    except Exception as _e:
        print(f"노트 대시보드 머지 실패: {_e}")
        cards = []

    severity = {"RED": 5, "ORANGE": 4, "BLUE": 3, "GRAY": 2, "BLACK": 1}
    cards.sort(key=lambda c: -severity.get(c["status"], 0))

    # 🟢 모델 단위 그룹핑 (신규 필드, 옛 cards 는 호환을 위해 그대로 유지)
    grouped_cards = _group_dashboard_cards(cards)

    return {"cards": cards, "grouped_cards": grouped_cards}

@app.get("/reports")
def list_reports():
    return {"reports": _read_json(LATEST_FILE, [])}


@app.get("/reports/{doc_id}/{product_name}")
def get_product_detail(doc_id: str, product_name: str):
    """제품 단위 상세 (기존 카드 탭용)"""
    latest = _read_json(LATEST_FILE, [])
    for report in latest:
        if report.get("doc_id") != doc_id:
            continue
        for p in report.get("products", []):
            name = p.get("product") or p.get("name", "")
            if name == product_name:
                return {
                    "doc_id": doc_id,
                    "report_date": (
                        report.get("report_meta", {}).get("date")
                        or report.get("report_date")
                    ),
                    "slide_images": report.get("slide_images", {}),
                    "section_images": report.get("section_images", {}),
                    **p,
                }
    raise HTTPException(status_code=404, detail="제품을 찾을 수 없습니다.")


# =========================================================
# 4. 프로젝트별 보기
# =========================================================
APP_VERSION_FILE = BASE_DIR / "app_version.json" if "BASE_DIR" in globals() else Path("app_version.json")
APP_APK_FILE = Path("app_release.apk")


@app.get("/app/version")
def get_app_version():
    """앱 시작 시 호출. 최신 버전 정보 반환."""
    try:
        with open("app_version.json", "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        data = {
            "latest_version": "1.0.0",
            "latest_version_code": 1,
            "download_url": "/app/download",
            "release_notes": "",
            "force_update": False,
        }
    return data


@app.get("/app/download")
def download_app_apk():
    """최신 APK 다운로드."""
    from fastapi.responses import FileResponse
    apk_path = Path("app_release.apk")
    if not apk_path.exists():
        raise HTTPException(status_code=404, detail="APK not uploaded yet")
    return FileResponse(
        path=str(apk_path),
        media_type="application/vnd.android.package-archive",
        filename="app_release.apk",
    )


NOTES_FILE = Path("notes.json")


def _load_notes() -> dict:
    try:
        with open(NOTES_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {"version": 1, "updated_at": None, "notes": {}}


def _save_notes(data: dict) -> None:
    from datetime import datetime
    data["updated_at"] = datetime.now().isoformat()
    with open(NOTES_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


# ─── 노트 첨부 자료 (표 JSON / 사진) 헬퍼 ───
import uuid as _uuid_mod
from datetime import datetime as _dt_mod

def _new_asset_id(division_id: str) -> str:
    """사업부별 자산 ID 생성: YYYY-MM-DD_<uuid8>"""
    date_str = _dt_mod.now().strftime("%Y-%m-%d")
    uid = _uuid_mod.uuid4().hex[:8]
    return f"{date_str}_{uid}"

def _table_path(division_id: str, asset_id: str) -> Path:
    div_dir = NOTE_TABLES_DIR / division_id
    div_dir.mkdir(parents=True, exist_ok=True)
    return div_dir / f"{asset_id}.json"

def _photo_path(division_id: str, asset_id: str, ext: str = "jpg") -> Path:
    div_dir = NOTE_PHOTOS_DIR / division_id
    div_dir.mkdir(parents=True, exist_ok=True)
    return div_dir / f"{asset_id}.{ext}"

def _save_note_table(division_id: str, table_data: dict) -> str:
    """표 JSON 저장 → asset_id 반환 (예: 'semiconductor/2026-06-11_a1b2c3d4')"""
    asset_id = _new_asset_id(division_id)
    p = _table_path(division_id, asset_id)
    p.write_text(json.dumps(table_data, ensure_ascii=False, indent=2), encoding="utf-8")
    return f"{division_id}/{asset_id}"

def _load_note_table(table_ref: str):
    """table_ref = 'semiconductor/2026-06-11_a1b2c3d4' → 표 JSON 반환"""
    if not table_ref or "/" not in table_ref:
        return None
    division_id, asset_id = table_ref.split("/", 1)
    p = _table_path(division_id, asset_id)
    if not p.exists():
        return None
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return None

def _delete_note_table(table_ref: str) -> bool:
    if not table_ref or "/" not in table_ref:
        return False
    division_id, asset_id = table_ref.split("/", 1)
    p = _table_path(division_id, asset_id)
    if p.exists():
        p.unlink()
        return True
    return False

def _delete_note_photo(photo_ref: str) -> bool:
    """photo_ref = 'semiconductor/2026-06-11_a1b2c3d4.jpg'"""
    if not photo_ref or "/" not in photo_ref:
        return False
    p = NOTE_PHOTOS_DIR / photo_ref
    if p.exists():
        p.unlink()
        return True
    return False


_NOTE_AI_SYSTEM_PROMPT = """당신은 회사 임원에게 보고되는 주간 보고서를 구조화하는 도우미입니다.

입력으로 들어오는 자유 형식 텍스트를 다음 JSON 스키마로 변환하세요:

{
  "cards": [
    {
      "title": "프로젝트 이름",
      "sections": [
        {
          "title": "섹션 이름",
          "items": [
            {"type": "bullet | highlight | sub | group_note", "text": "항목 내용", "group_id": "g1 (선택)"}
          ]
        }
      ]
    }
  ]
}

규칙:
1. <텍스트>로 감싼 것은 새 카드(프로젝트)
2. 줄 시작에 "1.", "2.", "3." 같은 숫자+점으로 시작하는 줄은 무조건 새 섹션(section)이다. 절대 item으로 만들지 마라.
   - 예: "1. 양산 14종" → section title="양산 14종"
   - 예: "2. 개발 18종" → section title="개발 18종"
   - 예: "3. EMA 33종 (총 33종 중 승인 7종, 개발 26종)" → section title="EMA 33종 (총 33종 중 승인 7종, 개발 26종)"
3. "1)", "2)" 같은 괄호 번호나 들여쓰기는 일반 item(bullet) — section 만들지 마라
4. *로 시작하거나 "현황:" 표시는 type: highlight
4-1. 색상 태그 처리 — 본문에 "[빨간색]" / "[파란색]" / "[주황색]" / "[노란색]" 이 포함된 항목은:
     - 태그 문자열만 제거하고 본문은 그대로 유지
     - 결과 JSON 아이템에 "color": "red" / "blue" / "orange" 필드를 추가
     - 색상 태그는 group_id 부여의 신호가 아니다 (색깔이 같다고 묶지 말 것)
     - 예: "[파란색] W23 출하 24EA" → {"type":"bullet","text":"W23 출하 24EA","color":"blue"}
5. "-", "▸"로 시작하는 줄은 type: bullet
6. "→", "=>", "↳" 또는 명백한 들여쓰기는 type: sub (상위 항목의 부가 설명)
7. "※" 로 시작하는 줄은 type: highlight (참고/주의)
   - "※" 기호는 절대 제거하지 말고 본문 첫 글자로 그대로 유지한다 (예: "※에테르GDX 자재 ...")
   - "※" 로 시작하는 모든 줄은 반드시 출력 JSON 에 포함시켜야 한다 (절대 누락 금지, 요약/병합 금지)
   - 카드 마지막에 있는 "※" 줄들은 가장 가까운(직전) 섹션의 items 끝에 그대로 추가한다
   - "※" 줄을 별도 "기타 특이사항" 섹션으로 옮기지 말고, 원문이 속한 섹션 안에 그대로 둔다
   - "※" 줄에는 group_id 를 절대 부여하지 않는다
8. 카드 제목·섹션 제목에서 선행 번호와 기호는 제거
9. item 텍스트에서 선행 기호(-, *, ▸)는 제거. 본문 안의 →, ↳는 유지
10. "📷 파일명 @@photo_ref=..." 줄은 절대 수정/요약/제거하지 말고 그 자리에 그대로 한 줄 유지
11. 의미는 절대 바꾸지 말고, 임의로 항목을 합치거나 추가하지 마라
12. 빈 항목·중복 항목은 만들지 마라

★ group_id 부여 조건 (중요 — 함부로 묶지 말 것):

다음 신호 중 하나라도 명시적으로 존재할 때만 group_id를 부여한다:
  (a) 줄 끝에 "}" 기호가 있는 경우
  (b) "←", "<—", "<-" 화살표가 줄 시작이나 끝에 있는 경우
  (c) 텍스트에 "포괄적으로 들어가야", "공통으로 적용", "모두 해당" 같은 명시적 표현이 있는 경우

위 신호가 전혀 없으면 group_id를 절대 부여하지 마라. (일반 bullet들을 마음대로 묶지 말 것)

★ 사진 placeholder 규칙 (매우 중요, 절대 어기지 말 것):
  - 본문에 "[PHOTO_KEEP_0]", "[PHOTO_KEEP_1]" 같은 토큰이 포함된 줄이 있으면:
    1) 그 줄 전체를 반드시 별도 item 으로 만들 것 (다른 줄과 병합 금지, 삭제 금지, 요약 금지)
    2) item 의 text 는 원문 그대로 ("📷 파일명 [PHOTO_KEEP_0]") 유지
    3) item 의 type 은 "bullet" 로 둔다
    4) 원문에서 그 줄이 있던 위치 그대로 보존 — 앞뒤 내용 순서 절대 변경 금지, 카드 끝으로 옮기지 말 것
    5) placeholder 줄을 group_id 의 신호로 사용하지 말 것

★ group_id 를 부여하면 안 되는 경우 (오해 방지):
  - 색상 태그([빨간색]/[파란색]/[주황색]/[노란색])만으로는 group_id 부여 금지
  - 같은 섹션에 속한다는 이유로 묶지 말 것
  - 의미가 비슷하다는 이유로 묶지 말 것
  - "※" 로 시작하는 줄은 묶지 말 것

group_id를 부여하는 경우 처리 방법:
  1) 신호가 나타난 줄 바로 위쪽의 연관된 bullet 2-3개에 동일한 group_id ("g1", "g2", ...) 부여
  2) 공통 메모는 별도 항목으로 추가: {"type":"group_note","text":"<메모 본문>","group_id":"g1"}
  3) group_note의 text 에서는 "}", "←" 같은 메타 기호 제거하고 본문만 남긴다

[예시 1 — 번호 소제목]
입력:
<파워박스>
1. 양산 14종
- 에테르 GDX : 연간 1,461대

2. 개발 18종
- 화성 세이버 5종 7월말 승인 타겟

출력:
{
  "cards": [{
    "title": "파워박스",
    "sections": [
      {"title": "양산 14종", "items": [
        {"type":"bullet","text":"에테르 GDX : 연간 1,461대"}
      ]},
      {"title": "개발 18종", "items": [
        {"type":"bullet","text":"화성 세이버 5종 7월말 승인 타겟"}
      ]}
    ]
  }]
}

[예시 2 — } 마커가 있을 때만 group_id]
입력:
<하바플레이트>
*현황: 총141개 모델 중 양산진행 14종
- 신규 장비 40대
- 플라스틱 전용 장비 6대 } 6월말 고객사 승인 예정

출력:
{
  "cards": [{
    "title": "하바플레이트",
    "sections": [
      {"title": "현황", "items": [
        {"type":"highlight","text":"총141개 모델 중 양산진행 14종"},
        {"type":"bullet","text":"신규 장비 40대","group_id":"g1"},
        {"type":"bullet","text":"플라스틱 전용 장비 6대","group_id":"g1"},
        {"type":"group_note","text":"6월말 고객사 승인 예정","group_id":"g1"}
      ]}
    ]
  }]
}

응답은 반드시 위 JSON 형식 한 객체만 출력. 마크다운, 코드블록, 설명 없이 JSON만 출력하세요."""


@app.post("/admin/notes/from_pptx")
def admin_notes_from_pptx(payload: dict, _admin: int = Depends(get_admin_session)):
    """업로드된 PPT를 주간 보고 카드 구조로 자동 변환.
    - 슬라이드 텍스트는 AI로 카드 구조화
    - 표는 자동으로 note_assets/tables/ 에 저장 + table_ref 연결
    """
    doc_id = (payload or {}).get("doc_id", "").strip()
    division_id = (payload or {}).get("division_id", "").strip()
    if not doc_id:
        raise HTTPException(status_code=400, detail="doc_id가 필요합니다")
    if not division_id:
        raise HTTPException(status_code=400, detail="division_id가 필요합니다")

    pptx_path = UPLOAD_DIR / f"{doc_id}.pptx"
    if not pptx_path.exists():
        raise HTTPException(status_code=404, detail=f"PPT 파일을 찾을 수 없음: {doc_id}")

    # 1) 텍스트 + 표 분리 추출
    try:
        slide_texts, slide_tables = _extract_pptx_text_and_tables(pptx_path)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"PPT 추출 실패: {e}")

    # 2) AI로 카드 구조 변환 (표 데이터는 텍스트로 함께 전달, AI가 표 참조 자리에 마커 삽입)
    joined_text = "\n\n".join([f"=== Slide {i+1} ===\n{t}" for i, t in enumerate(slide_texts) if t.strip()])
    if not joined_text.strip():
        return {"cards": []}

    user_message = (
        f"[PPT 텍스트 - 슬라이드별]\n{joined_text}\n\n"
        "위 PPT 텍스트를 주간 보고 카드 구조 JSON으로 변환해 주세요. "
        "한 슬라이드는 보통 한 프로젝트입니다. 슬라이드 제목이 프로젝트명입니다."
    )

    try:
        from openai import OpenAI
        import os
        oai = OpenAI(api_key=os.environ.get("OPENAI_API_KEY"))
        resp = oai.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": _NOTE_AI_SYSTEM_PROMPT},
                {"role": "user", "content": user_message},
            ],
            response_format={"type": "json_object"},
            temperature=0.1,
        )
        result = json.loads(resp.choices[0].message.content)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"AI 변환 실패: {e}")

    # 3) 표가 있는 슬라이드 → 자동 저장 + 첫 번째 섹션에 table_ref 부착
    cards = result.get("cards", []) or []
    saved_tables = []
    for slide_idx, tables in enumerate(slide_tables):
        if not tables:
            continue
        if slide_idx >= len(cards):
            continue
        card = cards[slide_idx]
        sections = card.get("sections", []) or []
        if not sections:
            continue
        # 첫 번째 표만 첫 섹션에 자동 첨부 (나머지는 별도 섹션으로)
        for t_idx, tbl in enumerate(tables):
            table_obj = {
                "title": card.get("title", "") + (f" 표{t_idx+1}" if t_idx > 0 else ""),
                "headers": tbl["headers"],
                "rows": tbl["rows"],
            }
            try:
                table_ref = _save_note_table(division_id, None, table_obj)
                saved_tables.append(table_ref)
                target_section = sections[0] if t_idx == 0 else sections[min(t_idx, len(sections)-1)]
                target_section["table_ref"] = table_ref
            except Exception as e:
                print(f"표 저장 실패 slide={slide_idx+1} t={t_idx}: {e}")

    return {"cards": cards, "saved_tables": saved_tables}


@app.get("/notes/by_project")
def notes_by_project(project_key: str = ""):
    """프로젝트 키로 가장 최근 노트 카드를 찾아 반환.
    매칭 우선순위:
      1) card.get("project_key") == project_key
      2) card.get("title") 가 projects.json 의 label/aliases 와 매칭
    표는 _load_note_table 으로 inline 포함.
    """
    project_key = (project_key or "").strip()
    if not project_key:
        raise HTTPException(status_code=400, detail="project_key 필요")

    try:
        proj = _cl.get_project(project_key)
    except Exception:
        proj = None
    project_label = (proj or {}).get("label", "")
    project_aliases = set((proj or {}).get("aliases", []) or [])
    project_division = (proj or {}).get("division_id", "")
    if project_label:
        project_aliases.add(project_label)
    project_aliases.add(project_key)

    data = _load_notes()
    notes_map = data.get("notes", {}) or {}

    # 사업부 우선 검색, 없으면 전체 사업부 스캔
    div_ids = [project_division] if project_division else list(notes_map.keys())
    if project_division and project_division not in notes_map:
        div_ids = list(notes_map.keys())

    best = None
    best_date = ""
    best_division = ""
    for did in div_ids:
        ndata = notes_map.get(did) or {}
        cards = ndata.get("cards", []) or []
        report_date = ndata.get("report_date", "") or ""
        for c in cards:
            ck = (c.get("project_key") or "").strip()
            ctitle = (c.get("title") or "").strip()
            matched = False
            if ck and ck == project_key:
                matched = True
            elif ctitle and (ctitle == project_label or ctitle in project_aliases):
                matched = True
            if not matched:
                continue
            # 가장 최근 날짜 선택
            if report_date > best_date:
                best = c
                best_date = report_date
                best_division = did

    if not best:
        return {"card": None}

    # table_ref inline 로드
    sections = best.get("sections", []) or []
    for sec in sections:
        # 섹션 레벨 table_ref (기존 호환)
        sec_ref = sec.get("table_ref")
        if sec_ref:
            try:
                sec["table_data"] = _load_note_table(sec_ref)
            except Exception:
                sec["table_data"] = None
        # 아이템 흐름 안의 table/photo
        items = sec.get("items", []) or []
        for it in items:
            if not isinstance(it, dict):
                continue
            t_ref = it.get("table_ref")
            if t_ref:
                try:
                    it["table_data"] = _load_note_table(t_ref)
                except Exception:
                    it["table_data"] = None

    return {
        "card": best,
        "report_date": best_date,
        "division_id": best_division,
    }






# ─── 노트 엑셀(표) 마커 전/후처리 (ai_parse 용) ───
_EXCEL_MARKER_RE = re.compile(
    "\U0001F4CA\s*([^\n\r]+?)\s*@@table_ref=([^\s\n\r]+)",
    re.IGNORECASE,
)

def _extract_excel_markers(text: str):
    """텍스트에서 엑셀 마커 추출.
    반환: (clean_text, [{filename, table_ref, anchor}])
    """
    lines = text.split("\n")
    out_lines = []
    tables = []
    last_nonempty = ""
    for ln in lines:
        m = _EXCEL_MARKER_RE.search(ln)
        if m:
            fname = (m.group(1) or "").strip()
            ref = (m.group(2) or "").strip()
            if fname and ref:
                tables.append({
                    "filename": fname,
                    "table_ref": ref,
                    "anchor": last_nonempty,
                })
            continue
        out_lines.append(ln)
        if ln.strip():
            last_nonempty = ln.strip()
    return ("\n".join(out_lines), tables)


def _inject_tables_into_cards(cards, tables):
    """정리된 카드 구조에 type:'table' item 을 앵커 기준으로 주입."""
    if not tables or not isinstance(cards, list):
        return cards

    def _norm(s):
        return re.sub(r"\s+", " ", str(s or "").strip().lower())

    used = set()

    for tb in tables:
        anchor_n = _norm(tb.get("anchor"))
        ref = tb.get("table_ref")
        fname = tb.get("filename") or ""
        if not ref or ref in used:
            continue

        # table_data 도 함께 로드해서 inline 포함
        table_data = _load_note_table(ref) if ref else None

        injected = False
        if anchor_n:
            for card in cards:
                if injected:
                    break
                for sec in (card.get("sections") or []):
                    if injected:
                        break
                    items = sec.get("items") or []
                    for idx, it in enumerate(items):
                        it_text = _norm(it.get("text") if isinstance(it, dict) else it)
                        if not it_text:
                            continue
                        if anchor_n == it_text or anchor_n in it_text or it_text in anchor_n:
                            new_item = {
                                "type": "table",
                                "text": fname,
                                "table_ref": ref,
                            }
                            if table_data:
                                new_item["table_data"] = table_data
                            items.insert(idx + 1, new_item)
                            sec["items"] = items
                            injected = True
                            used.add(ref)
                            break

        if not injected and cards:
            card0 = cards[0]
            secs = card0.setdefault("sections", [])
            if not secs:
                secs.append({"title": "첨부", "items": []})
            last_sec = secs[-1]
            new_item = {
                "type": "table",
                "text": fname,
                "table_ref": ref,
            }
            if table_data:
                new_item["table_data"] = table_data
            last_sec.setdefault("items", []).append(new_item)
            used.add(ref)

    return cards


# ─── 노트 사진 마커 전/후처리 (ai_parse 용) ───
import re as _re_photo
_PHOTO_MARKER_RE = _re_photo.compile(
    r"\u{1F4F7}\s*([^\n\r]+?)\s*@@photo_ref=([^\s\n\r]+)".replace(r"\u{1F4F7}", "\U0001F4F7"),
    _re_photo.IGNORECASE,
)

def _extract_photo_markers(text: str):
    """텍스트에서 사진 마커 추출 (next_anchor 기반 위치 보존).
    반환: (clean_text, [{filename, photo_ref, anchor, next_anchor, placeholder}])
    anchor      = 마커 직전의 비어있지 않은 줄
    next_anchor = 마커 다음에 나오는 비어있지 않은 줄 (마커가 아닌 줄)
    """
    lines = text.split("\n")

    marker_positions = []
    for i, ln in enumerate(lines):
        m = _PHOTO_MARKER_RE.search(ln)
        if m:
            fname = (m.group(1) or "").strip()
            ref = (m.group(2) or "").strip()
            if fname and ref:
                marker_positions.append((i, fname, ref))

    photos = []
    out_lines = []
    last_nonempty = ""
    marker_idx_set = {pos[0] for pos in marker_positions}

    def find_next_anchor(start):
        for j in range(start + 1, len(lines)):
            if j in marker_idx_set:
                continue
            v = lines[j].strip()
            if v:
                return v
        return ""

    pos_map = {pos[0]: pos for pos in marker_positions}
    for i, ln in enumerate(lines):
        if i in pos_map:
            _, fname, ref = pos_map[i]
            idx = len(photos)
            placeholder = f"[PHOTO_KEEP_{idx}]"
            placeholder_line = f"\U0001F4F7 {fname} {placeholder}"
            nxt = find_next_anchor(i)
            photos.append({
                "filename": fname,
                "photo_ref": ref,
                "anchor": last_nonempty,
                "next_anchor": nxt,
                "placeholder": placeholder,
            })
            out_lines.append(placeholder_line)
            last_nonempty = placeholder_line
            continue
        out_lines.append(ln)
        if ln.strip():
            last_nonempty = ln.strip()
    return ("\n".join(out_lines), photos)


_DONE_KEYWORDS = ("완료", "완료됨", "출고완료", "승인완료", "끝")
_PENDING_KEYWORDS = ("예정", "예상", "타겟", "목표", "진행중", "준비중", "까지", "예약")


def _split_for_date_scope(txt: str):
    """문장을 ',', '/', '|', '·' 기준으로 조각내서 (시작idx, 끝idx, 조각텍스트) 리스트 반환."""
    chunks = []
    start = 0
    for m in re.finditer(r"[,/|·]", txt):
        end = m.start()
        chunks.append((start, end, txt[start:end]))
        start = m.end()
    chunks.append((start, len(txt), txt[start:]))
    return chunks


def _is_done_scope(txt: str, idx: int) -> bool:
    """idx 위치의 날짜가 '완료된 날짜'인지 판정.
    한국어 어순: 날짜 → 키워드 (예: "5/29 승인완료", "W25 출하예정")
    규칙:
      1) idx 뒤에서 가장 가까이 나타나는 키워드(완료/예정)를 찾는다.
         - 완료 키워드면: 완료 (True, 날짜 버림)
         - 예정 키워드면: 살림 (False)
      2) idx 뒤에 키워드 없으면 idx 앞 12자 윈도우에 완료 키워드 있으면 완료.
      3) 그 외엔 살림.
    """
    if not txt:
        return False

    # 1) idx 뒤에서 가장 가까운 완료/예정 키워드 위치
    nearest_pos = -1
    nearest_kind = None  # 'done' or 'pending'
    for k in _DONE_KEYWORDS:
        i = txt.find(k, idx)
        if i != -1 and (nearest_pos == -1 or i < nearest_pos):
            nearest_pos = i
            nearest_kind = "done"
    for k in _PENDING_KEYWORDS:
        i = txt.find(k, idx)
        if i != -1 and (nearest_pos == -1 or i < nearest_pos):
            nearest_pos = i
            nearest_kind = "pending"

    # 같은 줄에서 너무 멀면 무시 (다른 절일 가능성)
    if nearest_pos != -1 and (nearest_pos - idx) <= 25:
        return nearest_kind == "done"

    # 2) idx 앞 12자 윈도우에 완료 키워드만 있으면 완료
    lo = max(0, idx - 12)
    front = txt[lo:idx]
    if any(k in front for k in _DONE_KEYWORDS) and not any(k in front for k in _PENDING_KEYWORDS):
        return True

    return False


def _extract_due_date_from_text(txt: str) -> str:
    """본문 텍스트에서 due_date(YYYY-MM-DD) 추출. 못 찾으면 빈 문자열.
    규칙:
      - "X월말" → 해당 월 마지막 평일(일요일이면 금요일)
      - "(M/D)", "M/D" → 2026-MM-DD
      - "W23"~"W53" → 해당 ISO 주차의 금요일 (연도 2026 기준)
      - "M월 D일", "M월D일" → 2026-MM-DD
      - "YYYY-MM-DD" / "YY.M.D" → 그대로
    여러 개 있으면 가장 빠른 날짜 채택.
    """
    from datetime import date, timedelta
    import calendar
    if not txt:
        return ""
    YEAR = 2026
    candidates = []

    # 1) YYYY-MM-DD
    for m in re.finditer(r"(20\d{2})-(\d{1,2})-(\d{1,2})", txt):
        try:
            if not _is_done_scope(txt, m.start()):
                candidates.append(date(int(m.group(1)), int(m.group(2)), int(m.group(3))))
        except Exception:
            pass

    # 2) YY.M.D
    for m in re.finditer(r"\b(\d{2})\.(\d{1,2})\.(\d{1,2})\b", txt):
        try:
            yy = 2000 + int(m.group(1))
            if not _is_done_scope(txt, m.start()):
                candidates.append(date(yy, int(m.group(2)), int(m.group(3))))
        except Exception:
            pass

    # 3) X월말 / X월 말 → 해당 월 마지막 평일(일요일이면 금요일)
    for m in re.finditer(r"(\d{1,2})\s*월\s*말", txt):
        try:
            mo = int(m.group(1))
            last_day = calendar.monthrange(YEAR, mo)[1]
            d = date(YEAR, mo, last_day)
            if d.weekday() == 6:  # 일요일이면 금요일로
                d = d - timedelta(days=2)
            if not _is_done_scope(txt, m.start()):
                candidates.append(d)
        except Exception:
            pass

    # 4) M월 D일 / M월D일
    for m in re.finditer(r"(\d{1,2})\s*월\s*(\d{1,2})\s*일", txt):
        try:
            if not _is_done_scope(txt, m.start()):
                candidates.append(date(YEAR, int(m.group(1)), int(m.group(2))))
        except Exception:
            pass

    # 5) (M/D) 또는 단독 M/D (단, 분수/비율은 제외 — 양쪽에 공백/괄호/조사 등 경계 있을 때만)
    for m in re.finditer(r"(?:^|[\s\(\[~])(\d{1,2})/(\d{1,2})(?=[\s\)\]\,\.~]|$)", txt):
        try:
            mo = int(m.group(1)); dd = int(m.group(2))
            if 1 <= mo <= 12 and 1 <= dd <= 31:
                if not _is_done_scope(txt, m.start()):
                    candidates.append(date(YEAR, mo, dd))
        except Exception:
            pass

    # 6) W23 ~ W53 → 해당 ISO 주차의 금요일
    for m in re.finditer(r"\bW\s*(\d{1,2})\b", txt, flags=re.IGNORECASE):
        try:
            wk = int(m.group(1))
            if 1 <= wk <= 53:
                d = date.fromisocalendar(YEAR, wk, 5)  # 5 = Friday
                if not _is_done_scope(txt, m.start()):
                    candidates.append(d)
        except Exception:
            pass

    if not candidates:
        return ""
    return min(candidates).isoformat()


def _normalize_note_item(it: dict) -> dict:
    """AI 결과 아이템 후처리: 색상 태그, ※ 항목, 화살표 중복 제거."""
    if not isinstance(it, dict):
        return it

    txt = (it.get("text") or "").strip()
    typ = (it.get("type") or "bullet").strip().lower()
    color = (it.get("color") or "").strip().lower()

    # [빨간색]/[파란색]/[주황색]/[노란색] -> color 필드로 승격, 본문에서는 제거
    if "[빨간색]" in txt:
        color = "red"
        txt = txt.replace("[빨간색]", "").strip()
    if "[파란색]" in txt:
        color = "blue"
        txt = txt.replace("[파란색]", "").strip()
    if "[주황색]" in txt:
        color = "orange"
        txt = txt.replace("[주황색]", "").strip()
    if "[노란색]" in txt:
        color = "orange"
        txt = txt.replace("[노란색]", "").strip()

    # ※ 로 시작하는 줄은 절대 group_note/특이사항으로 빼지 말고 일반 bullet 유지
    if txt.startswith("※"):
        if typ == "group_note":
            typ = "bullet"
        it.pop("group_id", None)

    # sub: 선행 화살표가 여러 개거나 중복이면 1개로 정규화
    if typ == "sub":
        txt = re.sub(r"^(?:\s*(?:→|↳|=>)\s*)+", "→ ", txt).strip()

    # bullet/highlight 도 "→ → ..." 처럼 화살표 중복 시 1개로 축약
    txt = re.sub(r"^(→\s*){2,}", "→ ", txt)

    it["type"] = typ
    it["text"] = txt
    if color:
        it["color"] = color

    # due_date 가 비어 있으면 본문에서 자동 추출
    if not (it.get("due_date") or "").strip():
        auto = _extract_due_date_from_text(txt)
        if auto:
            it["due_date"] = auto

    return it


def _normalize_note_cards(parsed: dict) -> dict:
    """parsed["cards"] 전체에 _normalize_note_item 적용 + 기타 특이사항 섹션 병합."""
    if not isinstance(parsed, dict):
        return parsed
    cards = parsed.get("cards") or []
    _ETC_TITLES = {"기타 특이사항", "기타특이사항", "특이사항", "기타"}
    for card in cards:
        if not isinstance(card, dict):
            continue

        # 1) 각 섹션 아이템 정규화
        for sec in (card.get("sections") or []):
            if not isinstance(sec, dict):
                continue
            new_items = []
            for it in (sec.get("items") or []):
                if isinstance(it, dict):
                    new_items.append(_normalize_note_item(it))
                else:
                    new_items.append(it)
            sec["items"] = new_items

        # 2) "기타 특이사항" 류 섹션은 직전 섹션에 흡수 후 삭제
        sections = card.get("sections") or []
        merged_sections = []
        for sec in sections:
            if not isinstance(sec, dict):
                merged_sections.append(sec)
                continue
            title = (sec.get("title") or "").strip()
            if title in _ETC_TITLES and merged_sections:
                # 직전 섹션 마지막에 합치기
                prev = merged_sections[-1]
                if isinstance(prev, dict):
                    prev_items = prev.get("items") or []
                    prev_items.extend(sec.get("items") or [])
                    prev["items"] = prev_items
                    continue
            merged_sections.append(sec)
        card["sections"] = merged_sections

    return parsed


def _inject_photos_into_cards(cards, photos):
    """정리된 카드 구조에 type:'photo' item 을 주입.
    1순위: placeholder 텍스트 ('__PHOTO_PLACEHOLDER_N__') 가진 item 을 photo item 으로 직접 치환 → 원문 위치 보존
    2순위(fallback): anchor 텍스트 매칭 (구버전 호환)
    """
    if not photos or not isinstance(cards, list):
        return cards

    def _norm(s):
        v = re.sub(r"^\s*\d+[.)\]]?\s*", "", str(s or "").strip())
        return re.sub(r"\s+", " ", v.lower())

    used = set()

    # ── 1순위: placeholder 직접 치환 ──
    for ph in photos:
        placeholder = ph.get("placeholder") or ""
        ref = ph.get("photo_ref")
        fname = ph.get("filename") or ""
        if not ref or not placeholder or ref in used:
            continue

        replaced = False
        for card in cards:
            if replaced:
                break
            for sec in (card.get("sections") or []):
                if replaced:
                    break
                items = sec.get("items") or []
                for idx, it in enumerate(items):
                    if not isinstance(it, dict):
                        continue
                    txt = str(it.get("text") or "")
                    if placeholder in txt:
                        # 해당 item 을 photo item 으로 치환
                        items[idx] = {
                            "type": "photo",
                            "text": fname,
                            "photo_ref": ref,
                        }
                        sec["items"] = items
                        replaced = True
                        used.add(ref)
                        break

        if replaced:
            continue

        # ── 1.5순위: next_anchor 매칭 (마커 다음 줄 앞에 삽입) ──
        next_anchor_n = _norm(ph.get("next_anchor"))
        if next_anchor_n:
            inserted_by_next = False
            # (a) item 텍스트 매칭 → 그 앞에 삽입
            for card in cards:
                if inserted_by_next:
                    break
                for sec in (card.get("sections") or []):
                    if inserted_by_next:
                        break
                    items = sec.get("items") or []
                    for idx, it in enumerate(items):
                        it_text = _norm(it.get("text") if isinstance(it, dict) else it)
                        if not it_text:
                            continue
                        if next_anchor_n == it_text or next_anchor_n in it_text or it_text in next_anchor_n:
                            items.insert(idx, {
                                "type": "photo",
                                "text": fname,
                                "photo_ref": ref,
                            })
                            sec["items"] = items
                            inserted_by_next = True
                            used.add(ref)
                            break
            # (b) section title 매칭 → 그 섹션의 첫 item 으로 삽입
            if not inserted_by_next:
                for card in cards:
                    if inserted_by_next:
                        break
                    for sec in (card.get("sections") or []):
                        sec_title = _norm(sec.get("title"))
                        if not sec_title:
                            continue
                        if next_anchor_n == sec_title or next_anchor_n in sec_title or sec_title in next_anchor_n:
                            items = sec.get("items") or []
                            items.insert(0, {
                                "type": "photo",
                                "text": fname,
                                "photo_ref": ref,
                            })
                            sec["items"] = items
                            inserted_by_next = True
                            used.add(ref)
                            break
            if inserted_by_next:
                continue

        # ── 2순위(fallback): anchor 텍스트 매칭 ──
        anchor_n = _norm(ph.get("anchor"))
        if anchor_n and anchor_n.startswith("__photo_placeholder_"):
            anchor_n = ""  # placeholder 자체는 anchor 로 쓰지 않음
        injected = False
        if anchor_n:
            # item 텍스트 매칭
            for card in cards:
                if injected:
                    break
                for sec in (card.get("sections") or []):
                    if injected:
                        break
                    items = sec.get("items") or []
                    for idx, it in enumerate(items):
                        it_text = _norm(it.get("text") if isinstance(it, dict) else it)
                        if not it_text:
                            continue
                        if anchor_n == it_text or anchor_n in it_text or it_text in anchor_n:
                            insert_at = idx + 1
                            matched_gid = (it.get("group_id") if isinstance(it, dict) else "") or ""
                            if matched_gid:
                                k = idx + 1
                                while k < len(items):
                                    nxt = items[k]
                                    if not isinstance(nxt, dict):
                                        break
                                    if (nxt.get("group_id") or "") != matched_gid:
                                        break
                                    insert_at = k + 1
                                    k += 1
                            else:
                                k = idx + 1
                                while k < len(items):
                                    nxt = items[k]
                                    if not isinstance(nxt, dict):
                                        break
                                    if (nxt.get("type") or "") != "group_note":
                                        break
                                    insert_at = k + 1
                                    k += 1
                            items.insert(insert_at, {
                                "type": "photo",
                                "text": fname,
                                "photo_ref": ref,
                            })
                            sec["items"] = items
                            injected = True
                            used.add(ref)
                            break

            # section title 매칭
            if not injected:
                for card in cards:
                    if injected:
                        break
                    for sec in (card.get("sections") or []):
                        sec_title = _norm(sec.get("title"))
                        if not sec_title:
                            continue
                        if anchor_n == sec_title or anchor_n in sec_title or sec_title in anchor_n:
                            items = sec.get("items") or []
                            items.insert(0, {
                                "type": "photo",
                                "text": fname,
                                "photo_ref": ref,
                            })
                            sec["items"] = items
                            injected = True
                            used.add(ref)
                            break

            # card title 매칭
            if not injected:
                for card in cards:
                    card_title = _norm(card.get("title"))
                    if not card_title:
                        continue
                    if anchor_n == card_title or anchor_n in card_title or card_title in anchor_n:
                        secs = card.setdefault("sections", [])
                        if not secs:
                            secs.append({"title": "첨부", "items": []})
                        secs[-1].setdefault("items", []).append({
                            "type": "photo",
                            "text": fname,
                            "photo_ref": ref,
                        })
                        injected = True
                        used.add(ref)
                        break

        # 앵커 못 찾으면 첫 카드 마지막 섹션 끝
        if not injected and cards:
            card0 = cards[0]
            secs = card0.setdefault("sections", [])
            if not secs:
                secs.append({"title": "첨부", "items": []})
            last_sec = secs[-1]
            last_sec.setdefault("items", []).append({
                "type": "photo",
                "text": fname,
                "photo_ref": ref,
            })
            used.add(ref)

    # ── 후처리: 사용되지 않은 placeholder item 제거 (AI 가 위치 보존 안 한 경우 대비) ──
    placeholder_re = re.compile(r"\[PHOTO_KEEP_\d+\]")
    for card in cards:
        for sec in (card.get("sections") or []):
            items = sec.get("items") or []
            sec["items"] = [
                it for it in items
                if not (isinstance(it, dict) and placeholder_re.match(str(it.get("text") or "").strip()))
            ]

    return cards


@app.post("/admin/notes/ai_parse")
def admin_notes_ai_parse(payload: dict, _admin: int = Depends(get_admin_session)):
    """자유 형식 텍스트를 AI로 구조화 JSON으로 변환 (증분 병합 지원)."""
    text = (payload or {}).get("text", "").strip()
    division_id = (payload or {}).get("division_id", "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="text가 비어있습니다")

    # 사진 마커 추출 (AI 가 보지 않도록 제거 후, 응답에 주입)
    text, _extracted_photos = _extract_photo_markers(text)
    text, _extracted_tables = _extract_excel_markers(text)

    user_message = f"다음 텍스트를 정리:\n\n{text}"

    try:
        from openai import OpenAI
        import os
        client = OpenAI(api_key=os.environ.get("OPENAI_API_KEY"))
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": _NOTE_AI_SYSTEM_PROMPT},
                {"role": "user", "content": user_message},
            ],
            response_format={"type": "json_object"},
            temperature=0.1,
        )
        content = response.choices[0].message.content
        parsed = json.loads(content)
        if isinstance(parsed, dict) and isinstance(parsed.get("cards"), list):
            parsed["cards"] = _inject_photos_into_cards(parsed["cards"], _extracted_photos)
            parsed = _normalize_note_cards(parsed)
            # parsed["cards"] = _inject_tables_into_cards(parsed["cards"], _extracted_tables)  # 엑셀은 photo로 처리
        return parsed
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"AI 파싱 실패: {str(e)}")


@app.post("/admin/notes")
def admin_save_note(payload: dict, _admin: int = Depends(get_admin_session)):
    """사업부별 노트 저장."""
    division_id = (payload or {}).get("division_id", "").strip()
    report_date = (payload or {}).get("report_date", "").strip()
    raw_text = (payload or {}).get("raw_text", "").strip()
    cards = (payload or {}).get("cards", [])

    if not division_id:
        raise HTTPException(status_code=400, detail="division_id 필수")
    if not isinstance(cards, list):
        raise HTTPException(status_code=400, detail="cards는 배열이어야 합니다")

    from datetime import datetime
    data = _load_notes()
    notes_map = data.setdefault("notes", {})
    existing = notes_map.get(division_id) or {}
    existing_cards = existing.get("cards") or []

    # 카드 제목 기준으로 merge (같은 title은 새 내용으로 교체, 새 title은 추가)
    def _norm_title(t):
        return re.sub(r"\s+", "", (t or "").strip()).lower()

    by_title = {}
    order = []
    for c in existing_cards:
        if not isinstance(c, dict):
            continue
        tkey = _norm_title(c.get("title"))
        if not tkey or tkey in by_title:
            continue
        by_title[tkey] = c
        order.append(tkey)

    for c in cards:
        if not isinstance(c, dict):
            continue
        tkey = _norm_title(c.get("title"))
        if not tkey:
            continue
        if tkey in by_title:
            by_title[tkey] = c  # 교체
        else:
            by_title[tkey] = c
            order.append(tkey)

    merged_cards = [by_title[k] for k in order]

    notes_map[division_id] = {
        "report_date": report_date or existing.get("report_date", ""),
        "updated_at": datetime.now().isoformat(),
        "raw_text": raw_text if isinstance(raw_text, str) else existing.get("raw_text", ""),
        "cards": merged_cards,
    }
    _save_notes(data)
    return {"ok": True, "division_id": division_id, "card_count": len(merged_cards)}


@app.get("/notes")
def get_notes(division_id: str = ""):
    """앱이 호출하는 공개 API. division_id 지정 시 해당 사업부만 반환."""
    data = _load_notes()
    notes = data.get("notes", {})
    if division_id:
        item = notes.get(division_id)
        if not item:
            return {"division_id": division_id, "report_date": "", "cards": [], "updated_at": None}
        return {"division_id": division_id, **item}
    return {"notes": notes}


@app.delete("/admin/notes/{division_id}")
def admin_delete_note(division_id: str, _admin: int = Depends(get_admin_session)):
    """노트 삭제."""
    data = _load_notes()
    if division_id in data.get("notes", {}):
        del data["notes"][division_id]
        _save_notes(data)
        return {"ok": True}
    raise HTTPException(status_code=404, detail="해당 사업부 노트 없음")



# ─── 노트 표/사진 첨부 API ───

# ─── 노트 표/사진 첨부 API ───
@app.post("/admin/notes/table")
def admin_save_note_table(payload: dict, _admin: int = Depends(get_admin_session)):
    """표 생성/수정. payload = {division_id, table_ref?, table: {title, headers, rows}}"""
    division_id = (payload or {}).get("division_id", "").strip()
    table = (payload or {}).get("table")
    existing_ref = (payload or {}).get("table_ref", "").strip()

    if not division_id:
        raise HTTPException(status_code=400, detail="division_id 필수")
    if not isinstance(table, dict):
        raise HTTPException(status_code=400, detail="table 필수")

    # 기존 표 수정인 경우 같은 파일에 덮어쓰기
    if existing_ref and "/" in existing_ref:
        div_id, asset_id = existing_ref.split("/", 1)
        p = _table_path(div_id, asset_id)
        p.write_text(json.dumps(table, ensure_ascii=False, indent=2), encoding="utf-8")
        return {"table_ref": existing_ref, "updated": True}

    # 신규 생성
    table_ref = _save_note_table(division_id, table)
    return {"table_ref": table_ref, "updated": False}


@app.get("/notes/table/{division_id}/{asset_id}")
def get_note_table(division_id: str, asset_id: str):
    """표 JSON 조회 (모바일/관리자 공용)"""
    table_ref = f"{division_id}/{asset_id}"
    data = _load_note_table(table_ref)
    if data is None:
        raise HTTPException(status_code=404, detail="표를 찾을 수 없음")
    return {"table_ref": table_ref, "table": data}


@app.delete("/admin/notes/table/{division_id}/{asset_id}")
def admin_delete_note_table(division_id: str, asset_id: str, _admin: int = Depends(get_admin_session)):
    table_ref = f"{division_id}/{asset_id}"
    ok = _delete_note_table(table_ref)
    if not ok:
        raise HTTPException(status_code=404, detail="표가 없음")
    return {"deleted": True, "table_ref": table_ref}


@app.post("/admin/notes/photo")
async def admin_upload_note_photo(
    division_id: str = Form(...),
    file: UploadFile = File(...),
    _admin: int = Depends(get_admin_session),
):
    """사진 업로드 → photo_ref(예: 'semiconductor/2026-06-11_abcd1234.jpg') 반환"""
    division_id = division_id.strip()
    if not division_id:
        raise HTTPException(status_code=400, detail="division_id 필수")

    # 확장자 결정
    orig_name = (file.filename or "").lower()
    ext = "jpg"
    for cand in ["jpg", "jpeg", "png", "gif", "webp"]:
        if orig_name.endswith("." + cand):
            ext = cand if cand != "jpeg" else "jpg"
            break

    asset_id = _new_asset_id(division_id)
    p = _photo_path(division_id, asset_id, ext)
    content = await file.read()
    p.write_bytes(content)
    photo_ref = f"{division_id}/{asset_id}.{ext}"
    return {"photo_ref": photo_ref, "url": f"/note_photos/{photo_ref}"}




# ─── 엑셀 업로드 (드래그&드롭) ───









def _excel_sheet_to_preview_data_url(ws):
    from io import BytesIO
    import base64
    from PIL import Image, ImageDraw, ImageFont, ImageChops

    NL = chr(10)

    def _effective_sheet_bounds():
        coords = []

        def _has_value(v):
            return v is not None and str(v).strip() != ""

        def _has_border(cell):
            try:
                b = cell.border
                return any([
                    b.left and b.left.style,
                    b.right and b.right.style,
                    b.top and b.top.style,
                    b.bottom and b.bottom.style,
                ])
            except Exception:
                return False

        def _has_fill(cell):
            try:
                f = cell.fill
                if f and f.fgColor and f.fgColor.rgb:
                    rgb = str(f.fgColor.rgb)
                    # 투명/흰색 제외
                    if rgb not in ("00000000", "FFFFFFFF", "FFFFFF", "None"):
                        return True
            except Exception:
                pass
            return False

        # 값 OR 테두리 OR 배경색 있는 셀 모두 포함
        for row in ws.iter_rows():
            for cell in row:
                if _has_value(cell.value) or _has_border(cell) or _has_fill(cell):
                    coords.append((cell.row, cell.column))

        # 병합 셀은 anchor 값이 있으면 병합 범위 전체 포함
        for rng in ws.merged_cells.ranges:
            min_col2, min_row2, max_col2, max_row2 = rng.bounds
            anchor = ws.cell(min_row2, min_col2)
            if _has_value(anchor.value) or _has_border(anchor) or _has_fill(anchor):
                coords.append((min_row2, min_col2))
                coords.append((max_row2, max_col2))

        if not coords:
            return 1, 1, 1, 1

        min_row2 = min(r for r, c in coords)
        max_row2 = max(r for r, c in coords)
        min_col2 = min(c for r, c in coords)
        max_col2 = max(c for r, c in coords)
        return min_row2, max_row2, min_col2, max_col2

    min_row, max_row, min_col, max_col = _effective_sheet_bounds()

    anchor_map = {}
    skip = set()
    for rng in ws.merged_cells.ranges:
        mc, mr, max_col2, max_row2 = rng.bounds
        anchor_map[(mr, mc)] = (max_row2, max_col2)
        for rr in range(mr, max_row2 + 1):
            for cc in range(mc, max_col2 + 1):
                if (rr, cc) != (mr, mc):
                    skip.add((rr, cc))

    # 한글 폰트 후보 (Mac → Linux/Railway 순)
    _font_candidates = [
        "/System/Library/Fonts/AppleSDGothicNeo.ttc",
        "/System/Library/Fonts/Supplemental/AppleGothic.ttf",
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/opentype/noto/NotoSansCJKkr-Regular.otf",
        "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/truetype/nanum/NanumGothic.ttf",
        "/usr/share/fonts/truetype/nanum/NanumBarunGothic.ttf",
    ]
    _font_bold_candidates = [
        "/System/Library/Fonts/AppleSDGothicNeo.ttc",
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
        "/usr/share/fonts/opentype/noto/NotoSansCJKkr-Bold.otf",
        "/usr/share/fonts/truetype/noto/NotoSansCJK-Bold.ttc",
        "/usr/share/fonts/truetype/nanum/NanumGothicBold.ttf",
        "/usr/share/fonts/truetype/nanum/NanumBarunGothicBold.ttf",
    ]

    def _load_font(candidates, size):
        import os
        for fp in candidates:
            if os.path.exists(fp):
                try:
                    return ImageFont.truetype(fp, size)
                except Exception:
                    continue
        return ImageFont.load_default()

    font = _load_font(_font_candidates, 22)
    font_bold = _load_font(_font_bold_candidates, 22)

    def text_size(txt, f):
        try:
            bbox = f.getbbox(txt)
            return bbox[2] - bbox[0], bbox[3] - bbox[1]
        except Exception:
            return (len(txt) * 11, 22)

    def format_value(cell):
        v = cell.value
        if v is None:
            return ""
        nf = (cell.number_format or "").lower()
        if isinstance(v, (int, float)) and ("#,##0" in nf or "0" in nf):
            try:
                iv = int(v)
                if iv == 0:
                    return "-"
                return f"{iv:,}" if iv >= 0 else f"-{abs(iv):,}"
            except Exception:
                return str(v)
        if isinstance(v, str):
            try:
                if v.strip() and v.strip().lstrip("-").isdigit():
                    iv = int(v)
                    if iv == 0:
                        return "-"
                    return f"{iv:,}" if iv >= 0 else f"-{abs(iv):,}"
            except Exception:
                pass
        return str(v)

    cell_text = {}
    for r in range(min_row, max_row + 1):
        for c in range(min_col, max_col + 1):
            cell_text[(r, c)] = format_value(ws.cell(r, c))
    
    col_widths = [0] * (max_col + 2)
    for c in range(min_col, max_col + 1):
        widest = 72
        for r in range(min_row, max_row + 1):
            if (r, c) in skip:
                continue
            t = cell_text.get((r, c), "")
            if not t:
                continue
            use_font = font_bold if (ws.cell(r, c).font and ws.cell(r, c).font.b) else font
            for line in t.split(NL):
                w, _ = text_size(line, use_font)
                if w + 24 > widest:
                    widest = min(w + 24, 320)
        col_widths[c] = widest

    row_heights = [0] * (max_row + 2)
    for r in range(min_row, max_row + 1):
        lines_max = 1
        for c in range(min_col, max_col + 1):
            t = cell_text.get((r, c), "")
            lines = max(1, t.count(NL) + 1)
            if lines > lines_max:
                lines_max = lines
        row_heights[r] = max(40, 14 + 26 * lines_max)

    # 표 범위만 그리도록 인덱스 맵 통일
    cols = list(range(min_col, max_col + 1))
    rows = list(range(min_row, max_row + 1))
    col_idx = {c: i for i, c in enumerate(cols)}
    row_idx = {r: i for i, r in enumerate(rows)}

    W = sum(col_widths[c] for c in cols)
    H = sum(row_heights[r] for r in rows)

    img = Image.new("RGB", (W, H), "white")
    draw = ImageDraw.Draw(img)

    xs = [0]
    for c in cols:
        xs.append(xs[-1] + col_widths[c])
    ys = [0]
    for r in rows:
        ys.append(ys[-1] + row_heights[r])

    def argb_to_hex(argb):
        if not argb:
            return None
        v = str(argb)
        if v in ("00000000", "None"):
            return None
        if len(v) == 8:
            v = v[2:]
        if len(v) == 6:
            try:
                int(v, 16)
                return "#" + v.lower()
            except Exception:
                return None
        return None

    def get_fill(cell):
        try:
            fg = cell.fill.fgColor
            if fg is not None and getattr(fg, "type", None) == "rgb":
                return argb_to_hex(fg.rgb)
        except Exception:
            pass
        return None

    def get_font_color(cell):
        try:
            c = cell.font.color
            if c is not None and getattr(c, "type", None) == "rgb":
                return argb_to_hex(c.rgb)
        except Exception:
            pass
        return None

    def is_dark(hex_color):
        try:
            v = hex_color.lstrip("#")
            r = int(v[0:2], 16)
            g = int(v[2:4], 16)
            b = int(v[4:6], 16)
            return (0.299 * r + 0.587 * g + 0.114 * b) < 160
        except Exception:
            return False

    for r in range(min_row, max_row + 1):
        for c in range(min_col, max_col + 1):
            if (r, c) in skip:
                continue
            x1, y1 = xs[col_idx[c]], ys[row_idx[r]]
            rr, cc = anchor_map.get((r, c), (r, c))
            x2, y2 = xs[col_idx[cc] + 1], ys[row_idx[rr] + 1]
            cell = ws.cell(r, c)
            bg = get_fill(cell) or "#ffffff"
            fc = get_font_color(cell)
            if not fc:
                fc = "#ffffff" if is_dark(bg) else "#111111"
            draw.rectangle([x1, y1, x2 - 1, y2 - 1], fill=bg, outline="#cbd5e1", width=1)
            val = cell_text.get((r, c), "")
            if val:
                lines = val.split(NL)
                line_h = 26
                total_h = line_h * len(lines)
                ty = y1 + max(4, ((y2 - y1) - total_h) // 2)
                use_font = font_bold if (cell.font and cell.font.b) else font
                cell_w = x2 - x1
                for li, line in enumerate(lines):
                    w, _ = text_size(line, use_font)
                    tx = x1 + max(4, (cell_w - w) // 2)
                    draw.text((tx, ty + li * line_h), line, fill=fc, font=use_font)

    # 마지막 흰 여백 소폭 trim
    try:
        bg = Image.new(img.mode, img.size, "white")
        diff = ImageChops.difference(img, bg)
        bbox = diff.getbbox()
        if bbox:
            l, t, r, b = bbox
            # 공백 최소화: 거의 딱 맞게 자르되 2px만 여유
            pad_x = 2
            pad_y = 2
            img = img.crop((
                max(0, l - pad_x),
                max(0, t - pad_y),
                min(img.width, r + pad_x),
                min(img.height, b + pad_y),
            ))
    except Exception:
        pass

    bio = BytesIO()
    img.save(bio, format="PNG")
    return "data:image/png;base64," + base64.b64encode(bio.getvalue()).decode("ascii")




@app.post("/admin/notes/excel")
async def admin_upload_note_excel(
    division_id: str = Form(...),
    file: UploadFile = File(...),
    _admin: int = Depends(get_admin_session),
):
    """엑셀(.xlsx/.xlsm) 업로드 → 첫 시트를 PNG 이미지로 변환 → 사진처럼 저장 → photo_ref 반환."""
    division_id = (division_id or "").strip()
    if not division_id:
        raise HTTPException(status_code=400, detail="division_id 필수")

    orig_name = file.filename or "upload.xlsx"
    lower = orig_name.lower()
    if not (lower.endswith(".xlsx") or lower.endswith(".xlsm")):
        raise HTTPException(status_code=400, detail="xlsx/xlsm 파일만 허용")

    raw = await file.read()
    if not raw:
        raise HTTPException(status_code=400, detail="빈 파일")

    try:
        import openpyxl
        from io import BytesIO
        import base64
        wb = openpyxl.load_workbook(BytesIO(raw), data_only=True)
        ws = wb.worksheets[0]
        data_url = _excel_sheet_to_preview_data_url(ws)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"엑셀 변환 실패: {e}")

    # data:image/png;base64,... → 바이트 디코드
    try:
        b64 = data_url.split(",", 1)[1]
        png_bytes = base64.b64decode(b64)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"PNG 디코딩 실패: {e}")

    asset_id = "xls_" + _new_asset_id(division_id)
    out_path = _photo_path(division_id, asset_id, "png")
    out_path.write_bytes(png_bytes)
    photo_ref = f"{division_id}/{asset_id}.png"

    return {
        "ok": True,
        "filename": orig_name,
        "photo_ref": photo_ref,
        "url": f"/note_photos/{photo_ref}",
    }

@app.delete("/admin/notes/photo/{division_id}/{filename}")
def admin_delete_note_photo(division_id: str, filename: str, _admin: int = Depends(get_admin_session)):
    photo_ref = f"{division_id}/{filename}"
    ok = _delete_note_photo(photo_ref)
    if not ok:
        raise HTTPException(status_code=404, detail="사진이 없음")
    return {"deleted": True, "photo_ref": photo_ref}


@app.get("/divisions")
def list_divisions():
    """공개 사업부 목록 + 각 사업부의 visible 프로젝트 리스트.
    매핑 관리 대시보드 / 모바일 사업부 화면에서 사용."""
    divs = _cl.get_divisions(visible_only=True)
    result = []
    for d in divs:
        div_id = d.get("id")
        # 해당 사업부의 visible 프로젝트만 (order 순)
        try:
            ps = _cl.get_projects(div_id, visible_only=True)
        except Exception:
            ps = []
        ps_sorted = sorted(ps, key=lambda x: x.get("order", 999))
        result.append({
            "id": div_id,
            "label": d.get("label"),
            "order": d.get("order", 999),
            "badge_short_label": d.get("badge_short_label"),
            "projects": [
                {
                    "id": p.get("id"),
                    "label": p.get("label"),
                    "order": p.get("order", 999),
                }
                for p in ps_sorted
            ],
        })
    result.sort(key=lambda x: x.get("order", 999))
    return {"divisions": result}


@app.get("/divisions/updates")
def get_divisions_updates():
    """각 사업부의 최신 업데이트 타임스탬프 반환.
    카드의 project_key 가 없을 수 있으므로 텍스트 기반 분류기를 사용한다.
    """
    try:
        with open(LATEST_FILE, "r", encoding="utf-8") as f:
            reports = json.load(f)
    except Exception:
        reports = []

    div_latest: dict[str, str] = {}

    for item in reports:
        ts = item.get("upload_timestamp") or ""
        products = item.get("products") or []
        for p in products:
            project_id = p.get("project_key") or p.get("project") or None
            if not project_id:
                parts = [
                    p.get("name") or "",
                    p.get("headline") or "",
                    " ".join(p.get("summary_bullets") or []),
                ]
                text = " ".join(s for s in parts if s)
                if text.strip():
                    try:
                        project_id = _cl.classify_project(text)
                    except Exception:
                        project_id = None

            div_id = _cl.derive_division_from_project(project_id) if project_id else None
            if not div_id:
                div_id = "unclassified"

            card_ts = p.get("updated_at") or ts
            if not card_ts:
                continue
            cur = div_latest.get(div_id, "")
            if card_ts > cur:
                div_latest[div_id] = card_ts

    all_divs = _cl.get_divisions(visible_only=True)
    result = []
    for d in all_divs:
        did = d.get("id")
        result.append({
            "division_id": did,
            "label": d.get("label"),
            "latest_updated_at": div_latest.get(did, ""),
        })

    return {"divisions": result}

@app.get("/projects")
def list_projects():
    """프로젝트 버튼 목록"""
    latest = _read_json(LATEST_FILE, [])
    grouped = aggregate_projects(latest)
    projects = [
        {
            "key": k,
            "label": v["label"],
            "status": v["status"],
            "report_date": v.get("report_date"),
        }
        for k, v in grouped.items()
    ]
    severity = {"RED": 3, "BLUE": 2, "BLACK": 1}

    # 🟢 프로젝트 목록 enrichment (기존 필드 변경 없음)
    projects = [enrich_project_entry(p) for p in projects]

    projects.sort(key=lambda p: -severity.get(p["status"], 0))
    return {"projects": projects}


@app.get("/projects/{project_key}")
def get_project_detail(project_key: str):
    """프로젝트 상세"""
    latest = _read_json(LATEST_FILE, [])
    grouped = aggregate_projects(latest)
    detail = build_project_detail(project_key, grouped)
    if not detail:
        # PPT 없어도 노트만 있으면 노트 카드로 응답
        try:
            notes_data = _read_json(NOTES_FILE, {})
            for div_id, div_obj in (notes_data.get("notes") or {}).items():
                for card in (div_obj.get("cards") or []):
                    if (card.get("title") or "").strip() == project_key.strip():
                        detail = {
                            "project_key": project_key,
                            "label": project_key,
                            "name": project_key,
                            "status": _calc_card_status(card),
                            "sections": card.get("sections") or [],
                            "note_only": True,
                            "report_date": div_obj.get("report_date"),
                            "updated_at": div_obj.get("updated_at"),
                        }
                        break
                if detail:
                    break
        except Exception as _e:
            pass
        if not detail:
            raise HTTPException(status_code=404, detail="프로젝트를 찾을 수 없습니다.")
    
    # 🟢 프로젝트 상세 enrichment (기존 필드 변경 없음)
    detail = enrich_project_detail(detail)

    # KPI 카드 자동 첨부 (project_key 별 화이트리스트)
    try:
        if project_key == "major_module":
            detail["kpi_card"] = _build_major_module_kpi_card()
            detail["issue_lines"] = _build_major_module_issue_lines()
    except Exception as _e:
        # KPI 계산 실패해도 기본 상세는 정상 반환되어야 함
        pass

    return detail


# =========================================================
# 5. 사용자 직접 차트/사진 업로드
# =========================================================
# ============================================================
# Admin Config API (5단계: admin 페이지 동적 dropdown용)
# - 운영 도구 페이지에서 사업부/프로젝트/섹션을 동적으로 로드하기 위한 API
# - 모두 GET, 인증 불필요 (admin 페이지 내부에서만 호출됨)
# ============================================================

@app.get("/admin/config/divisions")
def admin_config_divisions(_exp: int = Depends(get_admin_session)):
    """
    admin 페이지의 사업부 dropdown 용.
    config_loader.get_divisions() 결과를 그대로 노출.
    """
    try:
        items = _cl.get_divisions(visible_only=True)
        return {
            "divisions": [
                {
                    "id": d.get("id"),
                    "label": d.get("label"),
                    "mode": d.get("mode"),
                    "order": d.get("order"),
                    "badge_short_label": d.get("badge_short_label"),
                }
                for d in items
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"divisions load error: {e}")


@app.get("/admin/config/projects")
def admin_config_projects(division_id: str | None = None):
    """
    admin 페이지의 프로젝트 dropdown 용.
    division_id 가 주어지면 해당 사업부의 프로젝트만 반환.
    """
    try:
        items = _cl.get_projects(division_id=division_id, visible_only=True)
        return {
            "division_id": division_id,
            "projects": [
                {
                    "id": p.get("id"),
                    "label": p.get("label"),
                    "badge_label": p.get("badge_label"),
                    "group": p.get("group"),
                    "order": p.get("order"),
                }
                for p in items
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"projects load error: {e}")


@app.get("/admin/config/sections")
def admin_config_sections(project_key: str, _exp: int = Depends(get_admin_session)):
    """
    admin 이미지 업로드 탭의 섹션 dropdown 용.
    현재 분석된 PPT 결과에서 해당 프로젝트의 실제 GPT 섹션 제목들을 가져옴.
    이것이 핵심 — 더 이상 자유 입력 안 함, GPT 가 만든 실제 섹션만 옵션으로 노출.
    """
    try:
        latest = _read_json(LATEST_FILE, [])
        grouped = aggregate_projects(latest)
        detail = build_project_detail(project_key, grouped)
        if not detail:
            return {"project_key": project_key, "sections": []}

        sections = detail.get("sections", [])
        return {
            "project_key": project_key,
            "project_label": detail.get("label"),
            "sections": [
                {
                    "title": s.get("title"),
                    "image_count": len(s.get("image_urls", []) or []),
                }
                for s in sections
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"sections load error: {e}")


@app.get("/admin/config/stats")
def admin_config_stats(_exp: int = Depends(get_admin_session)):
    """
    매핑 관리 탭용 통계.
    - 현재 사업부/프로젝트 수
    - 자동 분류된 카드/실패 카드 수
    - 실패 카드의 product/category 샘플
    """
    try:
        divs = _cl.get_divisions(visible_only=True)
        all_projects = _cl.get_projects(visible_only=True)

        latest = _read_json(LATEST_FILE, [])
        total_cards = 0
        unclassified_cards = []
        for report in latest:
            for p in report.get("products", []):
                total_cards += 1
                name = p.get("name") or p.get("product", "")
                category = p.get("category", "")
                text = f"{name} {category}".strip()
                pid = _cl.classify_project(text)
                if not pid:
                    unclassified_cards.append({
                        "name": name,
                        "category": category,
                        "report_family": report.get("report_meta", {}).get("report_family", ""),
                    })

        return {
            "divisions_count": len(divs),
            "projects_count": len(all_projects),
            "total_cards": total_cards,
            "unclassified_count": len(unclassified_cards),
            "unclassified_samples": unclassified_cards[:20],
            "projects_by_division": {
                d.get("id"): [
                    {"id": p.get("id"), "label": p.get("label")}
                    for p in _cl.get_projects(division_id=d.get("id"), visible_only=True)
                ]
                for d in divs
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"stats load error: {e}")

# =========================================================
# 6. 어드민 페이지 (브라우저용)
# =========================================================


@app.get("/admin/v2", response_class=HTMLResponse)
def admin_v2_page(_exp: int = Depends(get_admin_session)):
    """OneView Admin v2 — 시안 기반 새 관리자 페이지."""
    return HTMLResponse(_ADMIN_V2_HTML)


_ADMIN_V2_HTML = """<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="utf-8">
<title>OneView Admin</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; height: 100%; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Pretendard", "Apple SD Gothic Neo", sans-serif; color: #1F2937; background: #F5F7FA; }
  a { color: inherit; text-decoration: none; }

  .app { display: flex; min-height: 100vh; }

  /* 좌측 사이드바 */
  .sidebar { width: 240px; flex-shrink: 0; background: #0B2B5C; color: #E5E7EB; padding: 22px 16px; display: flex; flex-direction: column; gap: 18px; }
  .sidebar .brand { display: flex; align-items: baseline; gap: 8px; padding: 0 6px; }
  .sidebar .brand .name { font-size: 22px; font-weight: 800; color: #fff; letter-spacing: -0.3px; }
  .sidebar .brand .sub { font-size: 12px; color: #93C5FD; font-weight: 600; }

  .biz-select { background: #12356F; border-radius: 10px; padding: 10px 12px; display: flex; flex-direction: column; gap: 4px; }
  .biz-select .label { font-size: 12px; color: #93C5FD; font-weight: 600; letter-spacing: 0.5px; }
  .biz-select select { background: transparent; color: #fff; border: none; font-size: 15px; font-weight: 600; padding: 2px 0; outline: none; cursor: pointer; }
  .biz-select select option { color: #111; }

  .nav-title { font-size: 12px; color: #93C5FD; letter-spacing: 1px; padding: 0 6px; font-weight: 700; }
  .nav { display: flex; flex-direction: column; gap: 4px; }
  .nav-item { display: flex; align-items: center; gap: 12px; padding: 12px 14px; border-radius: 10px; font-size: 15px; font-weight: 500; color: #CBD5E1; cursor: pointer; transition: background .15s, color .15s; }
  .nav-item:hover { background: rgba(255,255,255,0.06); color: #fff; }
  .nav-item.active { background: #fff; color: #0B2B5C; font-weight: 700; }
  .nav-item .icon { width: 22px; text-align: center; font-size: 16px; }

  .sidebar .spacer { flex: 1; }
  .sidebar .footer { font-size: 12px; color: #93C5FD; padding: 0 6px; opacity: 0.7; }

  /* 메인 */
  .main { flex: 1; display: flex; flex-direction: column; min-width: 0; }

  /* 상단 헤더 */
  .topbar { background: #fff; border-bottom: 1px solid #E5E7EB; padding: 16px 28px; display: flex; align-items: center; gap: 16px; }
  .breadcrumb { font-size: 13px; color: #6B7280; }
  .breadcrumb .sep { margin: 0 6px; color: #9CA3AF; }
  .breadcrumb .cur { color: #111827; font-weight: 600; }
  .topbar .grow { flex: 1; }
  .search { position: relative; }
  .search input { padding: 8px 12px 8px 34px; border: 1px solid #E5E7EB; border-radius: 999px; background: #F9FAFB; font-size: 13px; width: 220px; outline: none; }
  .search input:focus { border-color: #3B82F6; background: #fff; }
  .search::before { content: "🔍"; position: absolute; left: 12px; top: 50%; transform: translateY(-50%); font-size: 12px; opacity: 0.6; }
  .btn-primary { background: #0F2C59; color: #fff; border: none; border-radius: 8px; padding: 9px 16px; font-size: 13px; font-weight: 600; cursor: pointer; }
  .btn-primary:hover { background: #12356F; }

  /* 본문 영역 */
  .content { padding: 28px; flex: 1; }
  .page-title { font-size: 24px; font-weight: 800; color: #111827; margin: 0 0 4px 0; }
  .page-sub { font-size: 14px; color: #6B7280; margin: 0 0 20px 0; }

  .placeholder { background: #fff; border-radius: 14px; border: 1px solid #E5E7EB; padding: 60px 28px; text-align: center; color: #6B7280; }
  .placeholder .big { font-size: 40px; margin-bottom: 12px; opacity: 0.5; }
  .placeholder .title { font-size: 16px; font-weight: 700; color: #374151; margin-bottom: 6px; }
  .placeholder .sub { font-size: 13px; color: #9CA3AF; }
</style>
</head>
<body>
<div class="app">
  <!-- 사이드바 -->
  <aside class="sidebar">
    <div class="brand">
      <span class="name">OneView</span>
      <span class="sub">Admin</span>
    </div>

    <div class="biz-select">
      <span class="label">사업부</span>
      <select id="v2-division-select">
        <option value="semiconductor">반도체사업부</option>
      </select>
    </div>

    <div class="nav-title">MENU</div>
    <nav class="nav">
      <div class="nav-item" data-page="home"><span class="icon">🏠</span><span>홈 대시보드</span></div>
      <div class="nav-item active" data-page="report"><span class="icon">📄</span><span>보고</span></div>
      <div class="nav-item" data-page="production"><span class="icon">🏭</span><span>생산</span></div>
      <div class="nav-item" data-page="inbound"><span class="icon">📥</span><span>입고</span></div>
      <div class="nav-item" data-page="outbound"><span class="icon">📤</span><span>출하</span></div>
    </nav>

    <div class="spacer"></div>
    <div class="footer">v2 skeleton</div>
  </aside>

  <!-- 메인 -->
  <main class="main">
    <!-- 상단바 -->
    <div class="topbar">
      <div class="breadcrumb">
        <span id="v2-crumb-biz">반도체사업부</span>
        <span class="sep">›</span>
        <span class="cur" id="v2-crumb-page">보고</span>
      </div>
      <div class="grow"></div>
      <div class="search"><input type="text" placeholder="검색"></div>
      <button class="btn-primary">＋ 새 등록</button>
    </div>

    <!-- 페이지 컨텐츠 -->
    <div class="content" id="v2-content">
      <div id="ov-report-root"></div>
    </div>
  </main>
</div>

<script>
(function(){
  const PAGE_LABEL = {
    home: '홈 대시보드',
    report: '보고',
    production: '생산',
    inbound: '입고',
    outbound: '출하',
  };

  document.querySelectorAll('.nav-item').forEach(function(el){
    el.addEventListener('click', function(){
      document.querySelectorAll('.nav-item').forEach(function(x){ x.classList.remove('active'); });
      el.classList.add('active');
      const pg = el.getAttribute('data-page');
      document.getElementById('v2-crumb-page').textContent = PAGE_LABEL[pg] || pg;
      renderPage(pg);
    });
  });

  function renderPage(pg){
    const c = document.getElementById('v2-content');
    if (pg === 'report') {
      c.innerHTML = renderReportPageHTML();
      loadAdminV2Reports();
    } else {
      const icons = { home:'🏠', production:'🏭', inbound:'📥', outbound:'📤' };
      c.innerHTML = '<div class="placeholder"><div class="big">'+(icons[pg]||'✦')+'</div><div class="title">'+(PAGE_LABEL[pg]||pg)+'</div><div class="sub">개발 중 — 곧 오픈됩니다</div></div>';
    }
  }

  // ============================================================
  // Admin v2 · Report Page (KPI + Upload + List)
  // ============================================================
  window.renderReportPageHTML = function(){
    return `
      <style>
        .ov-page { padding: 0; }
        .ov-kpi-grid {
          display: grid;
          grid-template-columns: repeat(4, minmax(0, 1fr));
          gap: 16px;
          margin-bottom: 20px;
        }
        .ov-kpi-card {
          background: #fff;
          border: 1px solid #E6EBF2;
          border-radius: 20px;
          padding: 18px;
          box-shadow: 0 6px 18px rgba(15,44,89,0.04);
        }
        .ov-kpi-label { font-size: 13px; color: #6E7785; font-weight: 600; margin-bottom: 10px; }
        .ov-kpi-value { font-size: 28px; color: #0F2C59; font-weight: 800; line-height: 1.1; margin-bottom: 6px; }
        .ov-kpi-sub { font-size: 13px; color: #7A8595; font-weight: 600; }

        .ov-upload-card {
          background: #fff;
          border: 1px solid #E6EBF2;
          border-radius: 24px;
          padding: 24px;
          margin-bottom: 20px;
          box-shadow: 0 6px 18px rgba(15,44,89,0.04);
        }
        .ov-upload-drop {
          border: 2px dashed #BFD2EA;
          background: #F7FBFF;
          border-radius: 22px;
          padding: 34px 20px;
          text-align: center;
        }
        .ov-upload-icon { font-size: 34px; margin-bottom: 10px; }
        .ov-upload-title { font-size: 22px; color: #173B72; font-weight: 800; margin-bottom: 8px; }
        .ov-upload-desc { font-size: 14px; color: #6F7B8C; margin-bottom: 16px; }
        .ov-upload-meta {
          display: inline-block; margin-top: 14px;
          background: #EEF4FB; color: #2E5B94;
          padding: 8px 12px; border-radius: 999px;
          font-size: 13px; font-weight: 700;
        }

        .ov-list-card {
          background: #fff;
          border: 1px solid #E6EBF2;
          border-radius: 24px;
          padding: 20px;
          box-shadow: 0 6px 18px rgba(15,44,89,0.04);
        }
        .ov-list-head { display:flex; justify-content:space-between; align-items:center; margin-bottom: 16px; }
        .ov-list-title { font-size: 20px; color: #173B72; font-weight: 800; }
        .ov-list-sub { font-size: 13px; color: #748092; font-weight: 600; }

        .ov-report-list { display: flex; flex-direction: column; gap: 14px; }
        .ov-report-item {
          display: grid;
          grid-template-columns: 6px 1fr auto;
          gap: 14px;
          align-items: stretch;
          border: 1px solid #E8EDF4;
          border-radius: 18px;
          overflow: hidden;
          background: #FCFDFE;
        }
        .ov-report-bar.orange { background: #F59E0B; }
        .ov-report-bar.red { background: #EF4444; }
        .ov-report-bar.green { background: #10B981; }
        .ov-report-main { padding: 16px 0; }
        .ov-report-project { font-size: 18px; color: #12325F; font-weight: 800; margin-bottom: 4px; }
        .ov-report-file { font-size: 13px; color: #738094; margin-bottom: 10px; }
        .ov-report-preview { font-size: 14px; color: #415064; font-weight: 600; }
        .ov-report-side {
          display: flex; flex-direction: column;
          justify-content: center; align-items: flex-end;
          gap: 10px; padding: 16px 16px 16px 0;
        }
        .ov-badge {
          display:inline-flex; align-items:center;
          border-radius: 999px; padding: 8px 12px;
          font-size: 12px; font-weight: 800;
        }
        .ov-badge.blue { background: #E7F0FB; color: #23538C; }
        .ov-badge.amber { background: #FFF3D9; color: #9A6700; }
        .ov-badge.green { background: #E7F8F0; color: #117A52; }
        .ov-open-btn {
          border: 0; border-radius: 12px;
          background: #0F2C59; color: #fff;
          padding: 10px 14px; font-size: 13px; font-weight: 800;
          cursor: pointer;
        }
        .ov-load-more { display:flex; justify-content:center; margin-top: 16px; }
        .ov-load-more button {
          border: 1px solid #DCE4EF; background: #fff; color: #35527C;
          border-radius: 999px; padding: 12px 18px;
          font-size: 14px; font-weight: 700; cursor: pointer;
        }
        @media (max-width: 1200px) { .ov-kpi-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
        @media (max-width: 760px) {
          .ov-kpi-grid { grid-template-columns: 1fr; }
          .ov-report-item { grid-template-columns: 6px 1fr; }
          .ov-report-side { grid-column: 2; align-items: flex-start; padding: 0 16px 16px 0; }
        }
      </style>

      <div class="ov-page">
        <div class="ov-kpi-grid">
          <div class="ov-kpi-card">
            <div class="ov-kpi-label">이번 주</div>
            <div class="ov-kpi-value" id="ov-kpi-week">-</div>
            <div class="ov-kpi-sub">업로드된 보고 수</div>
          </div>
          <div class="ov-kpi-card">
            <div class="ov-kpi-label">AI 처리중</div>
            <div class="ov-kpi-value" id="ov-kpi-ai">-</div>
            <div class="ov-kpi-sub">현재 처리 대기/진행</div>
          </div>
          <div class="ov-kpi-card">
            <div class="ov-kpi-label">검토 대기</div>
            <div class="ov-kpi-value" id="ov-kpi-review">-</div>
            <div class="ov-kpi-sub">관리자 확인 필요</div>
          </div>
          <div class="ov-kpi-card">
            <div class="ov-kpi-label">발행 완료</div>
            <div class="ov-kpi-value" id="ov-kpi-published">-</div>
            <div class="ov-kpi-sub">앱 반영 가능 상태</div>
          </div>
        </div>

        <div class="ov-upload-card">
          <div class="ov-upload-drop">
            <div class="ov-upload-icon">📤</div>
            <div class="ov-upload-title">보고 PPT를 여기로 끌어다 놓으세요</div>
            <div class="ov-upload-desc">또는 버튼으로 파일 선택 · .pptx / .ppt · 최대 50MB</div>
            <button class="btn-primary" type="button">파일 선택</button>
            <div class="ov-upload-meta">✨ 표 · 목록 · 이미지 자동 파싱</div>
          </div>
        </div>

        <div class="ov-list-card">
          <div class="ov-list-head">
            <div>
              <div class="ov-list-title">최근 보고</div>
              <div class="ov-list-sub">가장 최근 등록된 보고를 확인하세요</div>
            </div>
          </div>
          <div class="ov-report-list" id="ov-report-list">
            <div style="color:#9CA3AF;font-size:14px;padding:20px;text-align:center;">불러오는 중...</div>
          </div>
          <div class="ov-load-more">
            <button type="button">이전 보고 더 보기</button>
          </div>
        </div>
      </div>
    `;
  };

  window.loadAdminV2Reports = async function(){
    try {
      const res = await fetch('/reports');
      const data = await res.json();
      const reports = Array.isArray(data.reports) ? data.reports : [];

      const listEl = document.getElementById('ov-report-list');
      if (!listEl) return;

      const recent = reports.slice(0, 3);
      if (recent.length === 0) {
        listEl.innerHTML = '<div style="color:#9CA3AF;font-size:14px;padding:20px;text-align:center;">등록된 보고가 없습니다.</div>';
      } else {
        listEl.innerHTML = recent.map(function(r){
          const title = r.title || r.product_name || r.project_name || '제목 없음';
          const fileName = r.file_name || r.filename || '보고 파일';
          const size = r.file_size || '-';
          const preview = r.summary_text || r.summary || '보고 미리보기 내용이 여기에 표시됩니다.';
          const status = (r.status || 'published').toString().toLowerCase();

          let badgeClass = 'green';
          let badgeText = 'Published';
          let barClass = 'green';

          if (status.indexOf('processing') >= 0 || status.indexOf('ai') >= 0) {
            badgeClass = 'blue'; badgeText = 'AI processing'; barClass = 'orange';
          } else if (status.indexOf('review') >= 0 || status.indexOf('pending') >= 0) {
            badgeClass = 'amber'; badgeText = 'Review pending'; barClass = 'red';
          }

          return ''
            + '<div class="ov-report-item">'
            +   '<div class="ov-report-bar ' + barClass + '"></div>'
            +   '<div class="ov-report-main">'
            +     '<div class="ov-report-project">' + title + '</div>'
            +     '<div class="ov-report-file">' + fileName + ' · ' + size + '</div>'
            +     '<div class="ov-report-preview">' + preview + '</div>'
            +   '</div>'
            +   '<div class="ov-report-side">'
            +     '<div class="ov-badge ' + badgeClass + '">' + badgeText + '</div>'
            +     '<button class="ov-open-btn" type="button">열기</button>'
            +   '</div>'
            + '</div>';
        }).join('');
      }

      const published = reports.filter(function(r){
        return ((r.status || 'published') + '').toLowerCase().indexOf('published') >= 0;
      }).length;
      const review = reports.filter(function(r){
        const st = ((r.status || '') + '').toLowerCase();
        return st.indexOf('review') >= 0 || st.indexOf('pending') >= 0;
      }).length;
      const ai = reports.filter(function(r){
        const st = ((r.status || '') + '').toLowerCase();
        return st.indexOf('processing') >= 0 || st.indexOf('ai') >= 0;
      }).length;

      const wkEl = document.getElementById('ov-kpi-week');
      const aiEl = document.getElementById('ov-kpi-ai');
      const rvEl = document.getElementById('ov-kpi-review');
      const pbEl = document.getElementById('ov-kpi-published');
      if (wkEl) wkEl.textContent = String(recent.length || 0);
      if (aiEl) aiEl.textContent = String(ai);
      if (rvEl) rvEl.textContent = String(review);
      if (pbEl) pbEl.textContent = String(published || reports.length || 0);
    } catch (e) {
      console.error('loadAdminV2Reports failed', e);
    }
  };

  // 최초 진입 시 report 페이지 즉시 렌더
  document.addEventListener('DOMContentLoaded', function(){
    const root = document.getElementById('ov-report-root');
    if (root) {
      root.outerHTML = '<div id="v2-content-inner"></div>';
      const inner = document.getElementById('v2-content-inner');
      if (inner) {
        inner.innerHTML = window.renderReportPageHTML();
        window.loadAdminV2Reports();
      }
    }
  });

})();
</script>
</body>
</html>
"""

@app.get("/admin/upload", response_class=HTMLResponse)
def admin_upload_page(admin_auth: Optional[str] = Cookie(default=None)):
    if not _verify_session(admin_auth):
        return RedirectResponse(url="/admin/login?next=/admin/upload", status_code=302)
    return HTMLResponse(content=_ADMIN_UPLOAD_HTML)


@app.get("/admin/uploads/history")
def admin_uploads_history(_admin: int = Depends(get_admin_session)):
    """업로드된 PPT 목록 (삭제 UI용)"""
    items = _read_json(LATEST_FILE, [])
    history = []
    for item in items:
        doc_id = item.get("doc_id", "")
        history.append({
            "doc_id": doc_id,
            "file_name": item.get("file_name") or item.get("filename") or "",
            "upload_timestamp": item.get("upload_timestamp") or item.get("uploaded_at") or "",
            "product_count": len(item.get("products", [])),
            "slide_count": len(item.get("slide_images", {})),
        })
    # 최신 업로드 먼저
    history.sort(key=lambda x: x.get("upload_timestamp", ""), reverse=True)
    return {"items": history}


@app.delete("/admin/doc/{doc_id}")
def admin_delete_doc(doc_id: str, _admin: int = Depends(get_admin_session)):
    """PPT 파일 단위 삭제: reports_latest.json + 관련 폴더/파일 전부 정리"""
    import shutil
    # 1) reports_latest.json 에서 제거
    items = _read_json(LATEST_FILE, [])
    before = len(items)
    items = [it for it in items if it.get("doc_id") != doc_id]
    after = len(items)
    if before == after:
        raise HTTPException(status_code=404, detail="해당 doc_id를 찾을 수 없습니다.")
    _write_json(LATEST_FILE, items)

    # 2) 파일 시스템 정리
    removed = []
    pptx_path = UPLOAD_DIR / f"{doc_id}.pptx"
    if pptx_path.exists():
        pptx_path.unlink()
        removed.append(str(pptx_path.name))

    for folder_dir in [SLIDES_DIR, SLIDE_IMAGES_DIR, CROPPED_DIR]:
        target = folder_dir / doc_id
        if target.exists() and target.is_dir():
            shutil.rmtree(target)
            removed.append(f"{folder_dir.name}/{doc_id}/")

    # 3) upload_hashes.json 에서 제거
    try:
        idx = _load_upload_hash_index()
        new_idx = {k: v for k, v in idx.items() if v.get("doc_id") != doc_id}
        if len(new_idx) != len(idx):
            _save_upload_hash_index(new_idx)
            removed.append("upload_hash entry")
    except Exception:
        pass

    return {"ok": True, "doc_id": doc_id, "removed": removed, "remaining": after}


@app.post("/admin/docs/delete-batch")
def admin_delete_docs_batch(
    payload: dict,
    _admin: int = Depends(get_admin_session),
):
    """PPT doc_id 여러 개 일괄 삭제"""
    doc_ids = payload.get("doc_ids", []) if isinstance(payload, dict) else []
    if not isinstance(doc_ids, list):
        raise HTTPException(status_code=400, detail="doc_ids must be a list")

    removed = []
    failed = []
    for did in doc_ids:
        if not isinstance(did, str):
            continue
        try:
            admin_delete_doc(did, _admin=_admin)
            removed.append(did)
        except HTTPException as e:
            failed.append({"doc_id": did, "status": e.status_code, "detail": e.detail})
        except Exception as e:
            failed.append({"doc_id": did, "detail": str(e)})

    return {
        "ok": True,
        "removed_count": len(removed),
        "removed": removed,
        "failed": failed,
    }


@app.delete("/admin/card")
def admin_delete_card(
    doc_id: str,
    product_idx: int,
    _admin: int = Depends(get_admin_session),
):
    """카드(product) 1장 단위 삭제"""
    items = _read_json(LATEST_FILE, [])
    target = None
    for it in items:
        if it.get("doc_id") == doc_id:
            target = it
            break
    if not target:
        raise HTTPException(status_code=404, detail="해당 doc_id를 찾을 수 없습니다.")

    products = target.get("products", [])
    if product_idx < 0 or product_idx >= len(products):
        raise HTTPException(status_code=404, detail=f"product_idx 범위 초과 (0~{len(products)-1})")

    removed_product = products.pop(product_idx)
    target["products"] = products
    _write_json(LATEST_FILE, items)
    return {
        "ok": True,
        "doc_id": doc_id,
        "removed_product_name": removed_product.get("name") or removed_product.get("product"),
        "remaining_products": len(products),
    }


@app.post("/admin/reset")
def admin_reset(password: str = Form(...)):
    _has_session = bool(_verify_session(admin_auth))
    if not _has_session and password != UPLOAD_PASSWORD:
        raise HTTPException(status_code=401, detail="비밀번호가 틀립니다.")
    _write_json(LATEST_FILE, [])
    return {"ok": True, "message": "최신 데이터가 초기화되었습니다."}


# =========================================================
# 어드민 업로드 페이지 HTML
# =========================================================
_ADMIN_UPLOAD_HTML = """
<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>사업부 보고 관리자</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", sans-serif;
    background: #f5f7fa;
    color: #1f2937;
    line-height: 1.6;
  }
  header {
    background: #1E3A5F;
    color: white;
    padding: 20px 32px;
  }
  header h1 { font-size: 20px; font-weight: 700; }
  header .meta { font-size: 12px; color: #cbd5e1; margin-top: 4px; }

  nav.tabs {
    display: flex;
    background: white;
    border-bottom: 1px solid #e5e7eb;
    padding: 0 32px;
    gap: 8px;
    overflow-x: auto;
  }
  nav.tabs button {
    padding: 14px 20px;
    border: none;
    background: transparent;
    cursor: pointer;
    font-size: 15px;
    color: #6b7280;
    border-bottom: 3px solid transparent;
    transition: all 0.15s;
    font-weight: 500;
    white-space: nowrap;
  }
  nav.tabs button:hover { color: #1E3A5F; background: #f9fafb; }
  nav.tabs button.active {
    color: #1E3A5F;
    border-bottom-color: #1E3A5F;
    font-weight: 700;
  }

  main {
    max-width: 960px;
    margin: 0 auto;
    padding: 32px 20px;
  }
  .tab-content { display: none; }
  .tab-content.active { display: block; }

  .card {
    background: white;
    padding: 24px;
    border-radius: 12px;
    margin-bottom: 20px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.05);
  }
  .card h2 { margin: 0 0 16px; font-size: 18px; color: #1f2937; }

  label { display: block; margin: 14px 0 6px; font-weight: 600; font-size: 13px; color: #333; }
  input, select, textarea {
    width: 100%;
    padding: 10px;
    border: 1px solid #ddd;
    border-radius: 8px;
    font-size: 14px;
    background: white;
    font-family: inherit;
  }
  button {
    background: #1E3A5F;
    color: white;
    border: none;
    padding: 12px 24px;
    border-radius: 8px;
    font-size: 15px;
    font-weight: 600;
    cursor: pointer;
    margin-top: 16px;
  }
  button:hover { background: #2c4d75; }
  button.delete {
    background: #ff3b30;
    padding: 6px 12px;
    font-size: 13px;
    margin-top: 0;
  }
  button.delete:hover { background: #d92e26; }

  .image-item {
    display: flex;
    align-items: center;
    gap: 16px;
    padding: 12px;
    border-bottom: 1px solid #eee;
  }
  .image-item:last-child { border-bottom: none; }
  .image-item img {
    width: 80px;
    height: 60px;
    object-fit: cover;
    border-radius: 6px;
    border: 1px solid #ddd;
  }
  .image-item .info { flex: 1; font-size: 13px; color: #555; }
  .image-item .info strong { color: #1f2937; }
  .image-item .badges { margin-top: 4px; }
  .badge {
    display: inline-block;
    padding: 2px 8px;
    border-radius: 4px;
    font-size: 11px;
    background: #e5e7eb;
    color: #374151;
    margin-right: 4px;
  }
  .badge.section { background: #fff3cd; color: #856404; }

  #uploadMsg {
    margin-top: 12px;
    padding: 10px;
    border-radius: 6px;
    font-size: 14px;
  }
  #uploadMsg.success { background: #d4edda; color: #155724; }
  #uploadMsg.error { background: #f8d7da; color: #721c24; }

  /* 노트 첨부 (표/사진) 버튼 */
  .note-item-row { display: flex; align-items: flex-start; gap: 6px; }
  .note-item-text { flex: 1; }
  .note-attach-btn {
    background: transparent; border: 1px solid #d1d5db; color: #6b7280;
    padding: 2px 8px; font-size: 11px; border-radius: 4px; cursor: pointer;
    margin: 0; line-height: 1.4; white-space: nowrap;
  }
  .note-attach-btn:hover { background: #f3f4f6; color: #1E3A5F; border-color: #1E3A5F; }
  .note-attach-btn.has-attachment { background: #fef3c7; color: #92400e; border-color: #f59e0b; }
  .note-mini-table {
    margin: 6px 0 6px 28px; border-collapse: collapse; font-size: 12px;
    background: white; border: 1px solid #e5e7eb; border-radius: 4px;
  }
  .note-mini-table th, .note-mini-table td {
    border: 1px solid #e5e7eb; padding: 4px 8px; text-align: left;
  }
  .note-mini-table th { background: #f9fafb; font-weight: 600; color: #374151; }
  .note-mini-photo {
    margin: 6px 0 6px 28px; max-width: 200px; max-height: 120px;
    border-radius: 6px; border: 1px solid #e5e7eb; cursor: pointer; display: block;
  }
  .note-attach-controls { display: flex; gap: 4px; margin: 4px 0 0 28px; }
  .note-attach-controls button {
    font-size: 11px; padding: 2px 6px; margin: 0;
    background: #f3f4f6; color: #4b5563; border: 1px solid #d1d5db; border-radius: 4px;
  }
  .note-attach-controls button.danger { background: #fee2e2; color: #991b1b; border-color: #fca5a5; }

  /* 표 편집 모달 */
  .modal-overlay {
    display: none; position: fixed; inset: 0; background: rgba(0,0,0,0.5);
    z-index: 1000; justify-content: center; align-items: center;
  }
  .modal-overlay.show { display: flex; }
  .modal-box {
    background: white; border-radius: 12px; padding: 24px;
    max-width: 90vw; max-height: 90vh; overflow: auto; min-width: 520px;
  }
  .modal-box h3 { margin: 0 0 12px; color: #1E3A5F; font-size: 18px; }
  .modal-box .modal-input {
    width: 100%; padding: 8px 10px; border: 1px solid #d1d5db; border-radius: 6px;
    font-size: 13px; margin-bottom: 10px; box-sizing: border-box;
  }
  .modal-box textarea.modal-input { min-height: 80px; font-family: monospace; }
  .modal-box .modal-table {
    border-collapse: collapse; width: 100%; margin-bottom: 12px; font-size: 13px;
  }
  .modal-box .modal-table th, .modal-box .modal-table td {
    border: 1px solid #d1d5db; padding: 4px;
  }
  .modal-box .modal-table input {
    border: none; width: 100%; padding: 4px; font-size: 13px; box-sizing: border-box;
  }
  .modal-box .modal-table input:focus { outline: 2px solid #1E3A5F; }
  .modal-actions { display: flex; gap: 8px; justify-content: flex-end; margin-top: 12px; }
  .modal-actions button { margin: 0; padding: 8px 16px; font-size: 13px; }
  .modal-actions button.cancel { background: #6b7280; }
  .modal-actions button.danger { background: #dc2626; }

  /* 사진 확대 모달 */
  .photo-overlay {
    display: none; position: fixed; inset: 0; background: rgba(0,0,0,0.9);
    z-index: 1100; justify-content: center; align-items: center; cursor: pointer;
  }
  .photo-overlay.show { display: flex; }
  .photo-overlay img { max-width: 95vw; max-height: 95vh; }


  /* 매핑 관리 대시보드 */
  .map-chip {
    padding: 6px 12px; border: 1px solid #d1d5db; border-radius: 16px;
    background: white; color: #4b5563; font-size: 13px; cursor: pointer;
    transition: all 0.15s;
  }
  .map-chip:hover { background: #f3f4f6; border-color: #1E3A5F; color: #1E3A5F; }
  .map-chip.active { background: #1E3A5F; color: white; border-color: #1E3A5F; font-weight: 600; }
  .map-chip .count {
    display: inline-block; margin-left: 6px; padding: 1px 6px; border-radius: 8px;
    font-size: 11px; background: #e5e7eb; color: #374151;
  }
  .map-chip.active .count { background: rgba(255,255,255,0.25); color: white; }

  .map-pcard {
    background: white; border: 1px solid #e5e7eb; border-radius: 8px;
    padding: 12px 14px; transition: all 0.15s; cursor: default;
  }
  .map-pcard:hover { border-color: #1E3A5F; box-shadow: 0 2px 8px rgba(30,58,95,0.08); }
  .map-pcard .ptitle { font-size: 14px; font-weight: 600; color: #1f2937; margin-bottom: 8px; }
  .map-pcard .pmeta { display: flex; gap: 10px; font-size: 12px; color: #6b7280; }
  .map-pcard .pmeta .badge-ppt { color: #1E3A5F; }
  .map-pcard .pmeta .badge-note { color: #10b981; }
  .map-pcard .pmeta .badge-empty { color: #d1d5db; }

  .placeholder {
    background: white;
    border: 2px dashed #d1d5db;
    border-radius: 12px;
    padding: 60px 40px;
    text-align: center;
    color: #6b7280;
  }
  .placeholder .icon { font-size: 48px; margin-bottom: 16px; }
  .placeholder h3 { font-size: 18px; margin-bottom: 8px; color: #374151; }
  .placeholder p { font-size: 14px; }

  .footer-info {
    text-align: center;
    color: #9ca3af;
    font-size: 12px;
    padding: 24px;
  }

  /* Dropzone */
  .dropzone {
    border: 2px dashed #cbd5e1;
    border-radius: 10px;
    padding: 28px 16px;
    text-align: center;
    cursor: pointer;
    transition: all 0.15s ease;
    background: #f8fafc;
  }
  .dropzone:hover { border-color: #1E3A5F; background: #f1f5f9; }
  .dropzone.dragover { border-color: #1E3A5F; background: #e0e7ff; transform: scale(1.01); }
  .dz-icon { font-size: 36px; margin-bottom: 8px; }
  .dz-title { font-size: 14px; font-weight: 600; color: #1E3A5F; margin-bottom: 4px; }
  .dz-sub { font-size: 12px; color: #64748b; }
  .file-row {
    display: flex; justify-content: space-between; align-items: center;
    padding: 8px 12px; margin-top: 6px;
    background: #f8fafc; border-radius: 6px; border: 1px solid #e2e8f0;
  }
  .file-row-name { font-size: 13px; color: #1f2937; flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; margin-right: 8px; }
  .file-row-size { font-size: 11px; color: #6b7280; margin-right: 8px; }
  .file-row-remove { background: transparent; color: #b91c1c; border: none; cursor: pointer; font-size: 16px; padding: 0 4px; }
  .file-row-remove:hover { color: #7f1d1d; }

  
  /* Progress bar */
  .pf-row { padding: 10px 12px; border-bottom: 1px solid #f1f5f9; font-size: 13px; }
  .pf-head { display: flex; align-items: center; gap: 10px; margin-bottom: 6px; }
  .pf-status { width: 22px; text-align: center; font-size: 15px; }
  .pf-name { font-weight: 600; color: #1f2937; flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .pf-pct { color: #1E3A5F; font-weight: 700; min-width: 44px; text-align: right; }
  .pf-barwrap { background: #e5e7eb; border-radius: 999px; height: 8px; overflow: hidden; }
  .pf-bar { background: linear-gradient(90deg, #1E3A5F, #3b82f6); height: 100%; width: 0%; transition: width 0.18s ease; }
  .pf-bar.done { background: linear-gradient(90deg, #10b981, #059669); }
  .pf-bar.fail { background: linear-gradient(90deg, #ef4444, #b91c1c); }
  .pf-bar.warn { background: linear-gradient(90deg, #f59e0b, #d97706); }
  .pf-detail { margin-top: 6px; color: #6b7280; font-size: 12px; }
  .pf-total {
    display: flex; align-items: center; gap: 10px;
    background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px;
    padding: 10px 14px; margin-bottom: 12px; font-size: 13px;
  }
  .pf-total .pf-barwrap { flex: 1; height: 10px; }
  .pf-total-label { font-weight: 700; color: #1E3A5F; }
  .pf-total-pct { font-weight: 700; color: #1E3A5F; min-width: 44px; text-align: right; }

  </style>
</head>
<body>
<header style="display:flex;justify-content:space-between;align-items:flex-start;gap:16px;flex-wrap:wrap;">
  <div>
    <h1 style="margin:0;">📊 사업부 보고 관리자</h1>
    <div class="meta" id="header-meta">로딩 중...</div>
  </div>
  <div id="adminSessionBar" style="display:flex;align-items:center;gap:8px;background:#1E3A5F;color:#fff;padding:8px 12px;border-radius:8px;font-size:13px;white-space:nowrap;">
    <span>🔐 관리자 세션 유지 중</span>
    <span style="background:#0f2342;padding:3px 10px;border-radius:999px;">남은 시간 <strong id="adminSessionRemain">확인 중...</strong></span>
    <button type="button" id="adminExtendBtn" style="background:#3b82f6;color:#fff;border:none;border-radius:6px;padding:6px 10px;cursor:pointer;">8시간 연장</button>
    <button type="button" id="adminLogoutBtn" style="background:#ef4444;color:#fff;border:none;border-radius:6px;padding:6px 10px;cursor:pointer;">로그아웃</button>
  </div>
</header>

<nav class="tabs">
  <button class="tab-btn active" data-tab="ppt">📤 PPT 업로드</button>
  <button class="tab-btn" data-tab="notes">📝 주간 보고 업로드</button>
  <button class="tab-btn" data-tab="mapping">⚙️ 매핑 관리</button>
</nav>

<main>

  <!-- ============================== 탭 1: PPT 업로드 ============================== -->
  <section class="tab-content active" id="tab-ppt">
    <div class="card">
      <h2>📤 새 PPT 업로드</h2>
      <form id="pptUploadForm">
        <label for="pptPassword">업로드 비밀번호</label>
        <input type="password" id="pptPassword" placeholder="관리자 비밀번호" required />

        <label>PPT 파일 (여러 개 가능 · 드래그 & 드롭 지원)</label>
        <div id="pptDropzone" class="dropzone">
          <div class="dz-icon">📂</div>
          <div class="dz-title">여기로 PPT 파일을 드래그하거나 클릭해서 선택</div>
          <div class="dz-sub">.pptx / .ppt · 여러 번 추가 가능 · 중복 자동 제거</div>
          <input type="file" id="pptFiles" accept=".pptx,.ppt" multiple hidden />
        </div>
        <div id="pptFileListHeader" style="display:none; margin-top:12px; display:flex; justify-content:space-between; align-items:center;">
          <div id="pptFileCount" style="font-size:13px; color:#374151; font-weight:600;"></div>
          <button type="button" id="pptClearAll" style="background:#fee2e2; color:#b91c1c; border:none; padding:6px 12px; border-radius:6px; cursor:pointer; font-size:12px;">전체 비우기</button>
        </div>
        <div id="pptFileList" style="margin-top: 8px; font-size: 13px;"></div>

        <label for="reportFamily">리포트 패밀리 (선택)</label>
        <input type="text" id="reportFamily" placeholder="default" value="default" />

        <!-- 중복 허용은 업로드 시작 버튼 옆으로 이동 -->

        <details style="margin-top: 20px;">
          <summary style="cursor: pointer; font-weight: 600; color: #1E3A5F; padding: 10px 0;">
            ▼ 사전 매핑 (선택) — 모든 파일에 동일 적용
          </summary>
          <div style="padding: 12px 0; border-top: 1px solid #eee; margin-top: 8px;">
            <p style="font-size: 12px; color: #6b7280; margin-bottom: 12px;">
              자동 분류가 실패한 카드만 여기서 정한 값으로 폴백됩니다. 자동 분류 잘 되는 카드는 영향 없음.
            </p>

            <label for="pptDivision">사업부</label>
            <select id="pptDivision">
              <option value="">— 자동 분류 —</option>
            </select>

            <label for="pptProject">프로젝트</label>
            <select id="pptProject" disabled>
              <option value="">— 사업부 먼저 선택 —</option>
            </select>
          </div>
        </details>

        <div style="margin-top:16px;">
          <div style="display:flex; align-items:center; gap:12px;">
            <button type="submit" id="pptUploadBtn">업로드 시작</button>
            <label style="display:inline-flex; align-items:center; gap:6px; font-size:13px; padding:6px 10px; background:#f3f4f6; border-radius:6px; cursor:pointer; white-space:nowrap;">
              <input type="checkbox" id="allowDuplicateUpload" />
              <span>중복 허용</span>
            </label>
          </div>
          <div style="font-size:11px; color:#9ca3af; margin-top:6px;">
            기본 차단 · 같은 파일 다시 올릴 때만 체크
          </div>
        </div>
      </form>
    </div>

    <div class="card" id="uploadHistoryCard">
      <h2 style="display:flex; align-items:center; justify-content:space-between;">
        <span>🗂️ 업로드 내역</span>
        <span style="font-size:12px; font-weight:normal;">
          <label style="margin-right:8px;"><input type="checkbox" id="historySelectAll" /> 전체 선택</label>
          <button type="button" id="historyDeleteBtn" style="background:#fee2e2; color:#b91c1c; border:none; padding:6px 12px; border-radius:6px; cursor:pointer; font-size:12px;">선택 삭제</button>
        </span>
      </h2>
      <p style="color:#6b7280;font-size:13px;margin-top:-4px;">PPT 파일 단위로 삭제하면 관련 카드가 모두 제거됩니다.</p>
      <div id="uploadHistoryArea" style="overflow-x:auto;">
        <div style="color:#999;padding:16px;">불러오는 중...</div>
      </div>
    </div>
    <div class="card" id="pptProgressCard" style="display: none;">
      <h2>📊 업로드 진행</h2>
      <div id="pptProgressSummary" style="font-size: 14px; color: #374151; margin-bottom: 12px;"></div>
      <div id="pptProgressList"></div>
    </div>

  </section>

  <!-- ============================== 탭 2: 이미지 업로드 (기존 폼 그대로) ============================== -->

  <!-- ============================== 탭 3: 매핑 관리 ============================== -->
  <section class="tab-content" id="tab-notes">
    <div class="card">
      <h2>📝 주간 보고 업로드</h2>
      <p style="color:#6b7280;font-size:13px;margin-top:-4px;">담당자가 받은 주간 보고 텍스트를 그대로 붙여넣고, AI 정리 후 저장하면 사장님 앱에 표시됩니다.</p>

      <div style="display:flex;gap:12px;align-items:flex-end;margin:16px 0;flex-wrap:wrap;">
        <div>
          <label style="display:block;font-size:13px;color:#374151;margin-bottom:4px;">사업부</label>
          <select id="noteDivision" style="padding:8px 12px;border:1px solid #d1d5db;border-radius:6px;font-size:14px;min-width:180px;">
            <option value="">로딩 중...</option>
          </select>
        </div>
        <div>
          <label style="display:block;font-size:13px;color:#374151;margin-bottom:4px;">보고일자</label>
          <input type="date" id="noteReportDate" style="padding:8px 12px;border:1px solid #d1d5db;border-radius:6px;font-size:14px;" />
        </div>
        <button type="button" id="noteLoadBtn" style="padding:8px 14px;background:#e5e7eb;color:#374151;border:none;border-radius:6px;cursor:pointer;font-size:13px;">📥 기존 노트 불러오기</button>
      </div>

      <label style="display:block;font-size:13px;color:#374151;margin-bottom:4px;">원본 텍스트</label>
      <textarea id="noteRawText" placeholder="<페러데이 4T>&#10;1. LPM&#10; - 5호기, 6호기-테스트완료(4/3)&#10;..." style="width:100%;height:280px;padding:12px;border:1px solid #d1d5db;border-radius:6px;font-size:13px;font-family:'Menlo','Monaco',monospace;line-height:1.5;"></textarea>

      <div style="display:flex;gap:8px;margin-top:12px;flex-wrap:wrap;">
        <button type="button" id="noteAiParseBtn" style="padding:10px 18px;background:#3b82f6;color:white;border:none;border-radius:6px;cursor:pointer;font-size:14px;font-weight:500;">🤖 AI로 정리하기</button>

        <span id="noteStatus" style="align-self:center;font-size:13px;color:#6b7280;"></span>
      </div>
    </div>

    <div class="card" id="notePreviewCard" style="display:none;">
      <h2>✨ 미리보기 (앱에서 이렇게 보입니다)</h2>
      <div id="notePreviewArea" style="background:#f5f7fb;padding:16px;border-radius:8px;"></div>
    </div>
  </section>

  <section class="tab-content" id="tab-mapping">
    <div class="card">
      <h2>📊 사업부 ↔ 프로젝트 통합 대시보드</h2>
      <p style="color:#6b7280;font-size:13px;margin-bottom:14px;">사업부 칩을 클릭하면 해당 사업부의 프로젝트 리스트가 표시됩니다.</p>
      <div id="mappingDivisionChips" style="display:flex;flex-wrap:wrap;gap:8px;margin-bottom:14px;"></div>
      <div id="mappingDivisionMeta" style="font-size:13px;color:#6b7280;margin-bottom:10px;"></div>
      <div id="mappingProjectGrid" style="display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:12px;"></div>
      <div id="mappingEmpty" style="color:#9ca3af;padding:24px;text-align:center;display:none;">프로젝트가 등록되지 않은 사업부입니다.</div>
    </div>
  </section>


</main>

<div class="footer-info">
  v2 — 5단계 진행 중 ·
  <a href="/docs" target="_blank" style="color: #6b7280;">API Docs</a>
</div>

<script>
  // 헤더 시간 표시
  function updateHeaderTime() {
    const now = new Date();
    const wd = ['일','월','화','수','목','금','토'][now.getDay()];
    const ampm = now.getHours() < 12 ? '오전' : '오후';
    const h12 = now.getHours() % 12 || 12;
    const m = String(now.getMinutes()).padStart(2, '0');
    document.getElementById('header-meta').textContent =
      `마지막 새로고침: ${now.getMonth()+1}/${now.getDate()} (${wd}) ${ampm} ${h12}:${m}`;
  }
  updateHeaderTime();

  // 탭 전환
  // ─── PPT → 주간 보고 초안 생성 ───
  let _draftDocId = null;

  function openDraftModal(docId, fileName) {
    _draftDocId = docId;
    document.getElementById('draftModalFile').textContent = fileName || docId;
    document.getElementById('draftModalStatus').textContent = '';
    const wrap = document.getElementById('draftDivChips');
    wrap.innerHTML = '<span style="color:#999;">사업부 로딩 중...</span>';
    document.getElementById('draftDivModal').classList.add('show');

    fetch('/divisions', { credentials: 'same-origin' })
      .then(r => r.json())
      .then(data => {
        const divs = data.divisions || [];
        wrap.innerHTML = '';
        divs.forEach(d => {
          const chip = document.createElement('button');
          chip.type = 'button';
          chip.textContent = (d.badge_short_label || d.label) + ' (' + (d.projects ? d.projects.length : 0) + ')';
          chip.className = 'map-chip';
          chip.style.cursor = 'pointer';
          chip.onclick = () => runPptxDraft(d.id, d.label);
          wrap.appendChild(chip);
        });
      })
      .catch(e => {
        wrap.innerHTML = '<span style="color:#c00;">사업부 로드 실패: ' + e.message + '</span>';
      });
  }

  function closeDraftModal() {
    document.getElementById('draftDivModal').classList.remove('show');
    _draftDocId = null;
  }

  async function runPptxDraft(divisionId, divisionLabel) {
    const status = document.getElementById('draftModalStatus');
    status.textContent = '⏳ PPT 분석 중... (10-30초)';
    status.style.color = '#6b7280';
    try {
      const r = await fetch('/admin/notes/from_pptx', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'same-origin',
        body: JSON.stringify({ doc_id: _draftDocId, division_id: divisionId }),
      });
      if (!r.ok) {
        let detail = r.status;
        try { const err = await r.json(); detail = err.detail || detail; } catch(_){}
        status.textContent = '❌ 실패: ' + detail;
        status.style.color = '#c00';
        return;
      }
      const data = await r.json();
      const cards = data.cards || [];
      if (cards.length === 0) {
        status.textContent = '⚠️ 추출된 카드가 없습니다';
        status.style.color = '#c00';
        return;
      }
      // 1) 주간 보고 탭으로 전환
      document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
      document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
      const noteBtn = document.querySelector('.tab-btn[data-tab="notes"]');
      if (noteBtn) noteBtn.classList.add('active');
      document.getElementById('tab-notes').classList.add('active');

      // 2) 사업부 셀렉트 + 날짜 자동 설정
      const sel = document.getElementById('noteDivision');
      if (sel) sel.value = divisionId;
      const dateEl = document.getElementById('noteReportDate');
      if (dateEl && !dateEl.value) {
        const today = new Date();
        dateEl.value = today.toISOString().slice(0, 10);
      }

      // 3) 미리보기 자동 주입
      _noteParsedCards = cards;
      renderNotePreview(_noteParsedCards);
      const noteStatus = document.getElementById('noteStatus');
      if (noteStatus) {
        noteStatus.textContent = '✅ PPT에서 ' + cards.length + '개 카드 자동 생성 — 확인 후 저장하세요';
        noteStatus.style.color = '#16a34a';
      }
      closeDraftModal();
    } catch (e) {
      status.textContent = '❌ 오류: ' + e.message;
      status.style.color = '#c00';
    }
  }

  // ESC로 초안 모달 닫기
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      const m = document.getElementById('draftDivModal');
      if (m && m.classList.contains('show')) closeDraftModal();
    }
  });

  document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      const target = btn.dataset.tab;
      document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
      document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
      btn.classList.add('active');
      document.getElementById('tab-' + target).classList.add('active');
    });
  });

  // ============================== 기존 이미지 업로드 로직 (그대로 유지) ==============================

  // 사업부 목록 로드
  async function loadProjects() {
    try {
      const res = await fetch('/projects');
      const data = await res.json();
      const sel = document.getElementById('projectKey');
      if (!sel) return;
      data.projects.forEach(p => {
        const opt = document.createElement('option');
        opt.value = p.key;
        opt.textContent = p.label || p.key;
        sel.appendChild(opt);
      });
    } catch (e) {
      console.error('사업부 목록 로드 실패:', e);
    }
  }

  // 등록된 이미지 목록 로드
  

  
  // ============================================================
  // 업로드 내역 (PPT doc_id 단위 삭제)
  // ============================================================
  async function loadUploadHistory() {
    const area = document.getElementById('uploadHistoryArea');
    if (!area) return;
    try {
      const r = await fetch('/admin/uploads/history', { credentials: 'same-origin' });
      if (!r.ok) {
        area.innerHTML = '<div style="color:#c00;padding:16px;">권한이 없습니다. 다시 로그인하세요.</div>';
        return;
      }
      const j = await r.json();
      const items = j.items || [];
      if (items.length === 0) {
        area.innerHTML = '<div style="color:#999;padding:16px;">업로드된 PPT가 없습니다.</div>';
        return;
      }
      let html = '<table style="width:100%;border-collapse:collapse;font-size:13px;min-width:600px;">';
      html += '<thead><tr style="background:#f3f4f6;text-align:left;">';
      html += '<th style="padding:10px 8px;width:32px;text-align:center;"></th>';
      html += '<th style="padding:10px 8px;">업로드 일시</th>';
      html += '<th style="padding:10px 8px;">파일명 / doc_id</th>';
      html += '<th style="padding:10px 8px;text-align:center;">카드</th>';
      html += '<th style="padding:10px 8px;text-align:center;">슬라이드</th>';
      html += '<th style="padding:10px 8px;text-align:center;">삭제</th>';
      html += '</tr></thead><tbody>';
      items.forEach(it => {
        let tsLabel = '-';
        if (it.upload_timestamp) {
          try {
            tsLabel = new Date(it.upload_timestamp).toLocaleString('ko-KR', {
              year: '2-digit', month: '2-digit', day: '2-digit',
              hour: '2-digit', minute: '2-digit'
            });
          } catch (_) { tsLabel = it.upload_timestamp; }
        }
        const safeFname = (it.file_name || '(이름 없음)').replace(/</g, '&lt;');
        html += '<tr style="border-bottom:1px solid #e5e7eb;">';
        html += `<td style="padding:10px 8px;text-align:center;"><input type="checkbox" class="history-row-check" data-doc-id="${it.doc_id}"></td>`;
        html += `<td style="padding:10px 8px;white-space:nowrap;">${tsLabel}</td>`;
        html += `<td style="padding:10px 8px;">${safeFname}<br><small style="color:#999;">${it.doc_id}</small></td>`;
        html += `<td style="padding:10px 8px;text-align:center;">${it.product_count}</td>`;
        html += `<td style="padding:10px 8px;text-align:center;">${it.slide_count}</td>`;
        html += `<td style="padding:10px 8px;text-align:center;white-space:nowrap;">`
              + `<button data-doc-id="${it.doc_id}" data-file-name="${(it.file_name || '').replace(/"/g, '&quot;').replace(/</g, '&lt;')}" class="draft-btn" style="background:#3b82f6;color:#fff;border:none;padding:6px 10px;border-radius:6px;cursor:pointer;font-size:12px;margin-right:6px;">📝 초안</button>`
              + `<button onclick="deleteDoc('${it.doc_id}', ${it.product_count})" style="background:#ef4444;color:#fff;border:none;padding:6px 10px;border-radius:6px;cursor:pointer;font-size:12px;">삭제</button>`
              + `</td>`;
        html += '</tr>';
      });
      html += '</tbody></table>';
      area.innerHTML = html;
      // 초안 버튼 이벤트 바인딩
      area.querySelectorAll('.draft-btn').forEach(btn => {
        btn.addEventListener('click', () => {
          openDraftModal(btn.dataset.docId, btn.dataset.fileName);
        });
      });
    } catch (e) {
      area.innerHTML = `<div style="color:#c00;padding:16px;">불러오기 실패: ${e.message}</div>`;
    }
  }

  async function deleteDoc(docId, productCount) {
    if (!confirm(`정말 삭제하시겠습니까?\n\n관련 카드 ${productCount}개가 모두 제거되고\nPPT 파일과 슬라이드 이미지도 삭제됩니다.`)) return;
    try {
      const r = await fetch(`/admin/doc/${docId}`, {
        method: 'DELETE',
        credentials: 'same-origin'
      });
      if (!r.ok) {
        let detail = r.status;
        try { const err = await r.json(); detail = err.detail || detail; } catch (_) {}
        alert('삭제 실패: ' + detail);
        return;
      }
      const result = await r.json();
      alert(`✅ 삭제 완료\n남은 PPT: ${result.remaining}개`);
      loadUploadHistory();
    } catch (e) {
      alert('삭제 오류: ' + e.message);
    }
  }



  // ============================================================
  // 관리자 세션 UI
  // ============================================================
  let adminSessionExpiresAt = null;

  function fmtRemain(sec) {
    if (sec < 0) sec = 0;
    const h = Math.floor(sec / 3600);
    const m = Math.floor((sec % 3600) / 60);
    const s = sec % 60;
    if (h > 0) return `${h}시간 ${m}분`;
    if (m > 0) return `${m}분 ${s}초`;
    return `${s}초`;
  }

  async function refreshAdminSessionInfo() {
    try {
      const r = await fetch('/admin/session', { credentials: 'same-origin' });
      if (!r.ok) {
        location.href = '/admin/login?next=/admin/upload';
        return;
      }
      const j = await r.json();
      adminSessionExpiresAt = j.expires_at;

      // password input 숨김 + required 해제
      document.querySelectorAll('input[type="password"]').forEach(el => {
        el.required = false;
        const label = el.id ? document.querySelector(`label[for="${el.id}"]`) : null;
        if (label) label.style.display = 'none';
        el.style.display = 'none';
      });
    } catch (e) {
      console.error('session load fail', e);
    }
  }

  function tickAdminSessionRemain() {
    const el = document.getElementById('adminSessionRemain');
    if (!el || !adminSessionExpiresAt) return;
    const remain = adminSessionExpiresAt - Math.floor(Date.now() / 1000);
    el.textContent = fmtRemain(remain);
    if (remain <= 0) {
      location.href = '/admin/login?next=/admin/upload';
    }
  }

  document.getElementById('adminExtendBtn')?.addEventListener('click', async () => {
    const r = await fetch('/admin/extend', { method: 'POST', credentials: 'same-origin' });
    if (r.ok) {
      const j = await r.json();
      adminSessionExpiresAt = j.expires_at;
      tickAdminSessionRemain();
      alert('세션이 8시간 연장되었습니다.');
    } else {
      location.href = '/admin/login?next=/admin/upload';
    }
  });

  document.getElementById('adminLogoutBtn')?.addEventListener('click', async () => {
    await fetch('/admin/logout', { method: 'POST', credentials: 'same-origin' });
    location.href = '/admin/login?next=/admin/upload';
  });

  refreshAdminSessionInfo().then(() => {
    tickAdminSessionRemain();
    setInterval(tickAdminSessionRemain, 1000);
    // 5초마다 백엔드 핑(서버측 만료 즉시 감지)
    setInterval(refreshAdminSessionInfo, 5000);
  });

  // 탭/창 복귀 시 즉시 재검증
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      refreshAdminSessionInfo();
    }
  });
  window.addEventListener('focus', refreshAdminSessionInfo);


  // 초기 로드
  loadProjects();
  loadUploadHistory();

  // ============================================================
  // 5-2b-2: PPT 업로드 폼 (다중 파일 + 사전 매핑 + 진행 표시)
  // ============================================================

  // 사업부 dropdown 채우기
  async function loadDivisionsForPpt() {
    try {
      const res = await fetch('/admin/config/divisions');
      const data = await res.json();
      const sel = document.getElementById('pptDivision');
      data.divisions.forEach(d => {
        const opt = document.createElement('option');
        opt.value = d.id;
        opt.textContent = d.label;
        sel.appendChild(opt);
      });
    } catch (e) {
      console.error('사업부 로드 실패:', e);
    }
  }

  // 사업부 선택 시 프로젝트 dropdown 채우기
  document.getElementById('pptDivision').addEventListener('change', async (e) => {
    const divId = e.target.value;
    const projSel = document.getElementById('pptProject');
    projSel.innerHTML = '<option value="">— 자동 분류 —</option>';

    if (!divId) {
      projSel.disabled = true;
      projSel.innerHTML = '<option value="">— 사업부 먼저 선택 —</option>';
      return;
    }

    try {
      const res = await fetch('/admin/config/projects?division_id=' + encodeURIComponent(divId));
      const data = await res.json();
      data.projects.forEach(p => {
        const opt = document.createElement('option');
        opt.value = p.id;
        opt.textContent = p.label + (p.group ? ' (' + p.group + ')' : '');
        projSel.appendChild(opt);
      });
      projSel.disabled = false;
    } catch (e) {
      console.error('프로젝트 로드 실패:', e);
    }
  });

  // 파일 선택 시 목록 표시

  // 한 파일 업로드 (XHR 기반 진행률 % 반환)
  function uploadSinglePpt(file, password, reportFamily, divisionId, projectId, allowDuplicate, itemEl, onProgress) {
    return new Promise((resolve) => {
      const fd = new FormData();
      fd.append('file', file);
      fd.append('password', password);
      fd.append('report_family', reportFamily || 'default');
      if (divisionId) fd.append('division_id', divisionId);
      if (projectId) fd.append('project_id', projectId);
      if (allowDuplicate) fd.append('allow_duplicate', 'true');

      // 상태: 시작
      const statusEl = itemEl.querySelector('.pf-status');
      const pctEl = itemEl.querySelector('.pf-pct');
      const barEl = itemEl.querySelector('.pf-bar');
      const detailEl = itemEl.querySelector('.pf-detail');
      statusEl.textContent = '⬆️';
      detailEl.textContent = '업로드 중...';

      const xhr = new XMLHttpRequest();
      xhr.open('POST', '/upload', true);

      // 업로드 바이트 진행률 (0~90% 구간 사용, 서버 처리는 90~100% 마무리에서 채움)
      xhr.upload.onprogress = (ev) => {
        if (!ev.lengthComputable) return;
        const pct = Math.round((ev.loaded / ev.total) * 90);
        barEl.style.width = pct + '%';
        pctEl.textContent = pct + '%';
        if (typeof onProgress === 'function') onProgress(pct);
      };

      // 업로드 완료 → 서버 처리 단계로 전환
      xhr.upload.onload = () => {
        statusEl.textContent = '⚙️';
        detailEl.textContent = '서버 처리 중...';
        barEl.style.width = '95%';
        pctEl.textContent = '95%';
        if (typeof onProgress === 'function') onProgress(95);
      };

      xhr.onload = () => {
        let data = {};
        try { data = JSON.parse(xhr.responseText || '{}'); } catch (e) {}
        if (xhr.status === 409 && data && data.code === 'duplicate_upload') {
          barEl.style.width = '100%';
          barEl.classList.add('warn');
          pctEl.textContent = '중복';
          statusEl.textContent = '⚠️';
          detailEl.innerHTML = '<span style="color:#b45309;">' + (data.detail || '이미 업로드된 파일') + '</span>';
          if (typeof onProgress === 'function') onProgress(100);
          resolve({ ok: false, duplicate: true, file: file.name, file_key: fileKey(file), error: data.detail || 'duplicate upload' });
          return;
        }
        if (xhr.status >= 200 && xhr.status < 300 && data && data.ok !== false) {
          barEl.style.width = '100%';
          barEl.classList.add('done');
          pctEl.textContent = '100%';
          statusEl.textContent = '✅';
          detailEl.textContent = '카드 ' + (data.product_count || 0) + '개 추출 (슬라이드 ' + (data.slide_count || 0) + '장)';
          if (typeof onProgress === 'function') onProgress(100);
          resolve({ ok: true, file: file.name, file_key: fileKey(file), data });
        } else {
          const msg = (data && (data.detail || data.message)) || ('HTTP ' + xhr.status);
          barEl.classList.add('fail');
          statusEl.textContent = '❌';
          detailEl.innerHTML = '<span style="color:#dc2626;">' + msg + '</span>';
          if (typeof onProgress === 'function') onProgress(100);
          resolve({ ok: false, file: file.name, file_key: fileKey(file), error: msg });
        }
      };

      xhr.onerror = () => {
        barEl.classList.add('fail');
        statusEl.textContent = '❌';
        detailEl.innerHTML = '<span style="color:#dc2626;">네트워크 오류</span>';
        if (typeof onProgress === 'function') onProgress(100);
        resolve({ ok: false, file: file.name, file_key: fileKey(file), error: 'network error' });
      };

      xhr.send(fd);
    });
  }

  // 업로드 폼 submit

  // ============================================================
  // 5-2b-2: 누적 + 드래그&드롭 + 개별 삭제 + 전체 비우기
  // ============================================================
  let pptSelectedFiles = []; // 누적된 File 객체 배열

  function formatBytes(b) {
    if (b < 1024) return b + ' B';
    if (b < 1024*1024) return (b/1024).toFixed(1) + ' KB';
    return (b/1024/1024).toFixed(1) + ' MB';
  }

  function fileKey(f) { return f.name + '_' + f.size; }

  function renderPptFileList() {
    const listEl = document.getElementById('pptFileList');
    const headerEl = document.getElementById('pptFileListHeader');
    const countEl = document.getElementById('pptFileCount');
    const btn = document.getElementById('pptUploadBtn');

    listEl.innerHTML = '';
    if (pptSelectedFiles.length === 0) {
      headerEl.style.display = 'none';
      btn.textContent = '업로드 시작';
      btn.disabled = true;
      btn.style.opacity = '0.5';
      return;
    }

    headerEl.style.display = 'flex';
    countEl.textContent = pptSelectedFiles.length + '개 파일 선택됨';
    btn.textContent = pptSelectedFiles.length + '개 업로드';
    btn.disabled = false;
    btn.style.opacity = '1';

    pptSelectedFiles.forEach((f, idx) => {
      const row = document.createElement('div');
      row.className = 'file-row';
      row.innerHTML =
        '<div class="file-row-name">📄 ' + f.name + '</div>' +
        '<div class="file-row-size">' + formatBytes(f.size) + '</div>' +
        '<button type="button" class="file-row-remove" data-idx="' + idx + '" title="제거">✕</button>';
      listEl.appendChild(row);
    });

    listEl.querySelectorAll('.file-row-remove').forEach(b => {
      b.addEventListener('click', (e) => {
        const i = parseInt(e.currentTarget.getAttribute('data-idx'));
        pptSelectedFiles.splice(i, 1);
        renderPptFileList();
      });
    });
  }

  function addPptFiles(fileList) {
    const allowed = ['.pptx', '.ppt'];
    const existing = new Set(pptSelectedFiles.map(fileKey));
    let added = 0, skipped = 0;
    Array.from(fileList).forEach(f => {
      const lower = f.name.toLowerCase();
      if (!allowed.some(ext => lower.endsWith(ext))) { skipped++; return; }
      if (existing.has(fileKey(f))) { skipped++; return; }
      pptSelectedFiles.push(f);
      existing.add(fileKey(f));
      added++;
    });
    renderPptFileList();
    if (skipped > 0) console.log('skip(중복/비PPT):', skipped);
  }

  // 파일 선택 input change
  document.getElementById('pptFiles').addEventListener('change', (e) => {
    addPptFiles(e.target.files);
    e.target.value = ''; // 같은 파일 재선택 가능하도록
  });

  // 드롭존 클릭 → input 열기
  const dz = document.getElementById('pptDropzone');
  dz.addEventListener('click', () => document.getElementById('pptFiles').click());

  // 드래그 & 드롭
  ['dragenter','dragover'].forEach(ev => dz.addEventListener(ev, (e) => {
    e.preventDefault(); e.stopPropagation();
    dz.classList.add('dragover');
  }));
  ['dragleave','drop'].forEach(ev => dz.addEventListener(ev, (e) => {
    e.preventDefault(); e.stopPropagation();
    dz.classList.remove('dragover');
  }));
  dz.addEventListener('drop', (e) => {
    if (e.dataTransfer && e.dataTransfer.files) {
      addPptFiles(e.dataTransfer.files);
    }
  });

  // 페이지 전체 드래그 기본동작 방지
  ['dragover','drop'].forEach(ev => {
    window.addEventListener(ev, (e) => { e.preventDefault(); }, false);
  });

  // 전체 비우기
  document.getElementById('pptClearAll').addEventListener('click', () => {
    pptSelectedFiles = [];
    renderPptFileList();
  });

  // 초기 렌더 (버튼 비활성화)
  renderPptFileList();

  document.getElementById('pptUploadForm').addEventListener('submit', async (e) => {
    e.preventDefault();

    const files = pptSelectedFiles.slice();
    if (files.length === 0) {
      alert('PPT 파일을 1개 이상 선택해주세요.');
      return;
    }

    const password = document.getElementById('pptPassword').value;
    const reportFamily = document.getElementById('reportFamily').value || 'default';
    const divisionId = document.getElementById('pptDivision').value;
    const projectId = document.getElementById('pptProject').value;
    const allowDuplicate = document.getElementById('allowDuplicateUpload').checked;

    // 진행 영역 표시 + 초기화
    const progressCard = document.getElementById('pptProgressCard');
    const progressList = document.getElementById('pptProgressList');
    const progressSummary = document.getElementById('pptProgressSummary');
    // 진행카드를 업로드내역 위로 이동 (업로드 중에만 보임)
    const historyCard = document.getElementById('uploadHistoryCard');
    if (historyCard && progressCard && historyCard.parentNode) {
      historyCard.parentNode.insertBefore(progressCard, historyCard);
    }
    progressCard.style.display = 'block';
    progressList.innerHTML = '';
    progressSummary.textContent = `총 ${files.length}개 파일 처리 시작...`;

    // 전체 진행률 영역
    progressSummary.innerHTML = `
      <div class="pf-total">
        <span class="pf-total-label">전체 진행률</span>
        <span id="pfTotalText">0 / ${files.length}</span>
        <div class="pf-barwrap"><div class="pf-bar" id="pfTotalBar"></div></div>
        <span class="pf-total-pct" id="pfTotalPct">0%</span>
      </div>
    `;
    const totalBar = document.getElementById('pfTotalBar');
    const totalPct = document.getElementById('pfTotalPct');
    const totalText = document.getElementById('pfTotalText');

    // 각 파일별 진행 항목 생성
    const fileProgress = new Array(files.length).fill(0);
    const itemEls = files.map((f, idx) => {
      const div = document.createElement('div');
      div.className = 'pf-row';
      div.innerHTML = `
        <div class="pf-head">
          <span class="pf-status">⏳</span>
          <span class="pf-name">📄 ${f.name}</span>
          <span class="pf-pct">0%</span>
        </div>
        <div class="pf-barwrap"><div class="pf-bar"></div></div>
        <div class="pf-detail">대기 중</div>
      `;
      progressList.appendChild(div);
      return div;
    });

    function updateTotal() {
      const sum = fileProgress.reduce((a,b)=>a+b, 0);
      const pct = Math.round(sum / files.length);
      totalBar.style.width = pct + '%';
      totalPct.textContent = pct + '%';
      const doneCnt = fileProgress.filter(p => p >= 100).length;
      totalText.textContent = doneCnt + ' / ' + files.length;
    }

    // 업로드 버튼 비활성화
    const btn = document.getElementById('pptUploadBtn');
    btn.disabled = true;
    btn.textContent = '업로드 중...';

    // 순차 업로드 (파일별 % → 전체 진행률 합산)
    const results = [];
    for (let i = 0; i < files.length; i++) {
      const result = await uploadSinglePpt(
        files[i], password, reportFamily, divisionId, projectId, allowDuplicate, itemEls[i],
        (pct) => { fileProgress[i] = pct; updateTotal(); }
      );
      fileProgress[i] = 100;
      updateTotal();
      results.push(result);
    }

    // 완료 후 통계 (전체 진행률 바 아래에 결과 줄 추가)
    const ok = results.filter(r => r.ok).length;
    const fail = results.length - ok;
    const totalCards = results.filter(r => r.ok).reduce((s, r) => s + (r.data.product_count || 0), 0);
    const doneLine = document.createElement('div');
    doneLine.style.cssText = 'margin-top:4px; font-size:13px;';
    doneLine.innerHTML = '<strong>완료:</strong> ' + ok + '/' + files.length + '개 성공' +
      (fail > 0 ? ', <span style="color:#dc2626;">' + fail + '개 실패</span>' : '') +
      ' · 총 카드 <strong>' + totalCards + '개</strong> 추출';
    progressSummary.appendChild(doneLine);

    // 성공한 파일만 선택 목록에서 제거
    const successKeys = new Set(results.filter(r => r.ok).map(r => r.file_key));
    pptSelectedFiles = pptSelectedFiles.filter(f => !successKeys.has(fileKey(f)));
    renderPptFileList();

    // 버튼 복구
    btn.disabled = false;
    btn.textContent = '업로드 시작';

    // 이미지 탭의 사업부 목록 갱신 (새로 업로드된 PPT 의 프로젝트가 잡힐 수 있게)
    try { loadProjects(); } catch (e) {}

    // 업로드 내역 즉시 갱신
    try { loadUploadHistory(); } catch (e) {}

    // 5초 뒤 진행카드 숨김
    setTimeout(() => {
      const pc = document.getElementById('pptProgressCard');
      if (pc) pc.style.display = 'none';
    }, 5000);
  });

  // 업로드 내역 다중 선택 핸들러 (전체 선택 / 선택 삭제)
  document.addEventListener('change', (e) => {
    if (e.target && e.target.id === 'historySelectAll') {
      const checked = e.target.checked;
      document.querySelectorAll('.history-row-check').forEach(cb => { cb.checked = checked; });
    }
  });
  document.addEventListener('click', async (e) => {
    if (e.target && e.target.id === 'historyDeleteBtn') {
      const ids = Array.from(document.querySelectorAll('.history-row-check:checked'))
        .map(cb => cb.dataset.docId).filter(Boolean);
      if (ids.length === 0) { alert('삭제할 항목을 선택하세요.'); return; }
      if (!confirm(ids.length + '개의 업로드를 삭제할까요? PPT 파일과 관련 카드가 모두 제거됩니다.')) return;
      e.target.disabled = true;
      try {
        const r = await fetch('/admin/docs/delete-batch', {
          method: 'POST',
          credentials: 'include',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({doc_ids: ids})
        });
        if (r.status === 401) { location.href = '/admin/login'; return; }
        const d = await r.json();
        alert((d.removed_count || 0) + '개 삭제 완료');
        try { loadUploadHistory(); } catch(_){}
      } catch (err) {
        alert('삭제 실패: ' + err);
      } finally {
        e.target.disabled = false;
      }
    }
  });




  // PPT 탭 진입 시 dropdown 초기 채우기
  loadDivisionsForPpt();

  // ============================== 노트 관리 (사업부 보고) ==============================
  let _noteParsedCards = null;

  async function loadNoteDivisions() {
    try {
      const r = await fetch('/admin/config/divisions', { credentials: 'same-origin' });
      if (!r.ok) throw new Error('fetch failed');
      const data = await r.json();
      const sel = document.getElementById('noteDivision');
      if (!sel) return;
      sel.innerHTML = '';
      (data.divisions || []).forEach(d => {
        const opt = document.createElement('option');
        opt.value = d.id;
        opt.textContent = d.label;
        sel.appendChild(opt);
      });
    } catch (e) {
      console.error('사업부 로드 실패', e);
    }
  }

  // 보고일자 기본값 = 오늘
  function initNoteDate() {
    const el = document.getElementById('noteReportDate');
    if (!el) return;
    const today = new Date();
    const y = today.getFullYear();
    const m = String(today.getMonth() + 1).padStart(2, '0');
    const d = String(today.getDate()).padStart(2, '0');
    el.value = `${y}-${m}-${d}`;
  }

  

function showUploadDonePopup(cardCount, onClose) {
  // 기존 팝업 있으면 제거
  const oldBg = document.getElementById('uploadDoneBg');
  if (oldBg) oldBg.remove();

  const bg = document.createElement('div');
  bg.id = 'uploadDoneBg';
  bg.style.cssText = 'position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.45);z-index:9999;display:flex;align-items:center;justify-content:center;';

  const box = document.createElement('div');
  box.style.cssText = 'background:#fff;border-radius:14px;padding:28px 32px;min-width:300px;max-width:90%;box-shadow:0 10px 30px rgba(0,0,0,0.2);text-align:center;font-family:inherit;';

  box.innerHTML = '<div style="font-size:42px;margin-bottom:10px;">✅</div>'
    + '<div style="font-size:18px;font-weight:600;color:#111;margin-bottom:6px;">업로드 완료되었습니다</div>'
    + '<div style="font-size:14px;color:#6b7280;margin-bottom:20px;">' + cardCount + '개 카드가 저장되었습니다</div>'
    + '<button id="uploadDoneOk" style="background:#10b981;color:#fff;border:none;border-radius:8px;padding:10px 28px;font-size:15px;font-weight:600;cursor:pointer;">확인</button>';

  bg.appendChild(box);
  document.body.appendChild(bg);

  const ok = document.getElementById('uploadDoneOk');
  function close() {
    bg.remove();
    if (typeof onClose === 'function') onClose();
  }
  ok.addEventListener('click', close);
  bg.addEventListener('click', function(e){ if (e.target === bg) close(); });
}

function renderNotePreview(cards) {
  const area = document.getElementById('notePreviewArea');
  const card = document.getElementById('notePreviewCard');
  if (!area || !card) return;

  if (!cards || cards.length === 0) {
    card.style.display = 'none';
    area.innerHTML = '';
    return;
  }

  const esc = (s) => String(s == null ? '' : s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');

  const renderAttachBtns = (ci, si, ii) => {
    // disabled by request — 미리보기에서 표/사진 버튼 숨김
    return '';
  };

  const renderMiniTable = (table) => {
    if (!table) return '';
    const headers = Array.isArray(table.headers) ? table.headers : [];
    const rows = Array.isArray(table.rows) ? table.rows : [];
    const previewRows = rows.slice(0, 3);
    let html = `
      <div style="margin-top:8px;padding:10px;border:1px solid #d1d5db;border-radius:8px;background:#fafafa;">
        <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:6px;">
          <strong style="font-size:13px;">📊 ${esc(table.title || '표')}</strong>
          <span style="font-size:11px;color:#6b7280;">탭/클릭으로 확대·수정</span>
        </div>
        <div style="overflow-x:auto;">
          <table style="border-collapse:collapse;width:100%;font-size:12px;background:#fff;">
    `;
    if (headers.length) {
      html += '<thead><tr>';
      headers.forEach(h => {
        html += `<th style="border:1px solid #e5e7eb;padding:6px 8px;background:#f3f4f6;text-align:left;">${esc(h)}</th>`;
      });
      html += '</tr></thead>';
    }
    html += '<tbody>';
    previewRows.forEach(r => {
      html += '<tr>';
      (Array.isArray(r) ? r : []).forEach(c => {
        html += `<td style="border:1px solid #e5e7eb;padding:6px 8px;">${esc(c)}</td>`;
      });
      html += '</tr>';
    });
    html += '</tbody></table></div>';
    if (rows.length > 3) {
      html += `<div style="margin-top:4px;font-size:11px;color:#6b7280;">… 외 ${rows.length - 3}행</div>`;
    }
    html += '</div>';
    return html;
  };

  const renderDueChip = (dueRaw) => {
    if (!dueRaw) return '';
    const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(dueRaw);
    if (!m) return '';
    const due = new Date(parseInt(m[1]), parseInt(m[2])-1, parseInt(m[3]));
    const today = new Date();
    today.setHours(0,0,0,0);
    const diff = Math.round((due - today) / (1000*60*60*24));
    let bg = '#dbeafe', fg = '#1e40af', label;
    if (diff < 0) { bg = '#fee2e2'; fg = '#b91c1c'; label = `D+${-diff} 지남`; }
    else if (diff === 0) { bg = '#fef3c7'; fg = '#92400e'; label = 'D-0 오늘'; }
    else if (diff <= 3) { bg = '#fed7aa'; fg = '#9a3412'; label = `D-${diff}`; }
    else { label = `D-${diff}`; }
    const dateLabel = `${m[2]}/${m[3]}`;
    return `<span style="display:inline-block;margin-left:6px;padding:1px 7px;border-radius:10px;background:${bg};color:${fg};font-size:11px;font-weight:600;">${label} (${dateLabel})</span>`;
  };

  const renderPhoto = (photoRef) => {
    if (!photoRef) return '';
    const url = '/note_photos/' + photoRef;
    const isExcel = /\/xls_/.test(photoRef);
    if (isExcel) {
      return `
        <div style="margin:8px 0 14px 0;">
          <div style="background:#fff;border:1px solid #e5e7eb;border-radius:10px;padding:8px;overflow:auto;">
            <img src="${esc(url)}"
                 onclick="showPhotoOverlay('${esc(url)}')"
                 style="display:block;width:100%;height:auto;border-radius:6px;cursor:pointer;" />
          </div>
        </div>
      `;
    }
    return `
      <div style="margin-top:8px;">
        <img src="${esc(url)}"
             onclick="showPhotoOverlay('${esc(url)}')"
             style="max-width:240px;max-height:150px;border-radius:8px;border:1px solid #d1d5db;cursor:pointer;object-fit:cover;" />
      </div>
    `;
  };

  // 일반 항목 한 줄 렌더 (group 묶음 안/밖 공용)
  const renderOneItem = (it, ci, si, ii) => {
    if (typeof it === 'string') {
      it = { type: 'bullet', text: it };
    }
    if (!it || typeof it !== 'object') return '';
    const type = it.type || 'bullet';
    const text = esc(it.text || '');
    const hasTable = !!it.table_ref;
    const hasPhoto = !!it.photo_ref;
    const tableData = it.table_data || null;
    const photoRef = it.photo_ref || '';

    if (type === 'table') {
      if (tableData && tableData.preview_image_data) {
        const _safeTitle = String(it.text || tableData.title || '엑셀').replace(/[&<>"']/g, function(ch){
          return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch];
        });
        return `
          <div style="margin:8px 0 14px 0;">
            <div style="font-size:13px;font-weight:700;color:#334155;margin-bottom:6px;">📊 ${_safeTitle}</div>
            <div style="background:#fff;border:1px solid #e5e7eb;border-radius:10px;padding:8px;overflow:auto;">
              <img src="${tableData.preview_image_data}" style="display:block;max-width:100%;height:auto;border-radius:6px;" />
            </div>
          </div>
        `;
      }
      return ``;
    }
    if (type === 'photo') {
      return `<div style="margin:8px 0;">${renderPhoto(photoRef)}</div>`;
    }

    // 색상 매핑 (item.color > 타입 기본색)
    const _colorMap = { red:'#dc2626', blue:'#1e88e5', orange:'#ef6c00' };
    const itemColor = _colorMap[String(it.color || '').toLowerCase()] || '';

    let prefix = '•';
    let textStyle = 'font-size:14px;color:#111827;';
    let leftPad = '';
    const rawText = String(it.text || '').trim();
    const startsWithStar = rawText.startsWith('※');

    if (type === 'highlight') {
      textStyle = 'font-size:14px;color:#dc2626;font-weight:700;';
    } else if (type === 'sub') {
      // 화살표 중복 방지: 본문이 이미 → / ↳ / => 로 시작하면 prefix 비움
      prefix = /^(?:→|↳|=>)\s*/.test(rawText) ? '' : '→';
      textStyle = 'font-size:13px;color:#374151;';
      leftPad = 'padding-left:18px;';
    }

    // ※ 줄은 굵게 + 기본 검정 (color 지정 있으면 그게 우선)
    if (startsWithStar) {
      textStyle = 'font-size:14px;color:#111827;font-weight:700;';
      prefix = '';
    }

    // item.color 가 있으면 최종적으로 그 색으로 덮어쓰기 (font-weight 유지)
    if (itemColor) {
      textStyle = textStyle.replace(/color:[^;]+;?/, '') + 'color:' + itemColor + ';';
    }

    if (hasTable && !tableData && typeof loadTableDataForItem === 'function') {
      setTimeout(() => {
        try { loadTableDataForItem(it, () => renderNotePreview(_noteParsedCards)); } catch (_) {}
      }, 0);
    }

    const dueChip = renderDueChip(it.due_date || '');
    return `
      <div style="display:flex;align-items:flex-start;justify-content:space-between;gap:8px;margin:6px 0;${leftPad}">
        <div style="flex:1;min-width:0;">
          <div style="${textStyle}">${prefix} ${text} ${dueChip}</div>
          ${hasTable ? renderMiniTable(tableData) : ''}
          ${hasPhoto ? renderPhoto(photoRef) : ''}
        </div>
        ${renderAttachBtns(ci, si, ii)}
      </div>
    `;
  };

  // group_id 같은 항목들을 연속 구간으로 묶어 노란 박스로 렌더
  const renderItemsWithGroups = (items, ci, si) => {
    let html = '';
    let i = 0;
    while (i < items.length) {
      const raw = items[i];
      const it = (typeof raw === 'string') ? { type: 'bullet', text: raw } : (raw || {});
      const gid = it.group_id || '';

      if (gid) {
        // 같은 group_id 가진 연속 구간 모으기
        const groupItems = [];
        let j = i;
        while (j < items.length) {
          const r = items[j];
          const x = (typeof r === 'string') ? { type: 'bullet', text: r } : (r || {});
          if (x.group_id !== gid) break;
          groupItems.push({ raw: r, idx: j });
          j++;
        }

        // 노란 박스 시작
        html += `
          <div style="margin:8px 0;padding:10px 12px;border-left:4px solid #d97706;background:#fffbeb;border-radius:6px;">
        `;

        // group_note 와 일반 항목 분리
        const normals = groupItems.filter(g => {
          const o = (typeof g.raw === 'string') ? { type: 'bullet' } : (g.raw || {});
          return o.type !== 'group_note';
        });
        const notes = groupItems.filter(g => {
          const o = (typeof g.raw === 'string') ? { type: 'bullet' } : (g.raw || {});
          return o.type === 'group_note';
        });

        // 일반 항목 먼저
        normals.forEach(g => {
          html += renderOneItem(g.raw, ci, si, g.idx);
        });

        // group_note (있으면 박스 안 아래에)
        notes.forEach(g => {
          const o = (typeof g.raw === 'string') ? { type: 'group_note', text: g.raw } : g.raw;
          const text = esc(o.text || '');
          html += `
            <div style="margin:6px 0 0 4px;padding-top:6px;border-top:1px dashed #fcd34d;">
              <div style="font-size:13px;color:#92400e;font-style:italic;">↪ ${text} ${renderDueChip(o.due_date || '')}</div>
            </div>
          `;
        });

        html += `</div>`;
        i = j;
      } else {
        // group 아닌 일반 항목
        if (it.type === 'group_note') {
          // group_id 없는 group_note 도 노란 박스로 단독 표시
          const text = esc(it.text || '');
          html += `
            <div style="margin:8px 0 8px 18px;padding:8px 10px;border-left:4px solid #d97706;background:#fffbeb;border-radius:6px;">
              <div style="font-size:13px;color:#92400e;font-style:italic;">↪ ${text}</div>
            </div>
          `;
        } else {
          html += renderOneItem(raw, ci, si, i);
        }
        i++;
      }
    }
    return html;
  };

  let html = '';
  cards.forEach((c, ci) => {
    const title = esc(c.title || '');
    const sections = Array.isArray(c.sections) ? c.sections : [];
    html += `
      <div style="background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:16px;margin-bottom:16px;">
        <div style="font-weight:800;font-size:18px;margin-bottom:12px;">${title}</div>
    `;

    sections.forEach((s, si) => {
      const stitle = esc(s.title || '');
      const items = Array.isArray(s.items) ? s.items : [];
      html += `
        <div style="margin-bottom:12px;">
          <div style="background:#f5f7fb;border-radius:8px;padding:8px 10px;font-weight:700;margin-bottom:8px;">${stitle}</div>
      `;

      html += renderItemsWithGroups(items, ci, si);

      // 섹션 레벨 표 (구버전 호환)
      if (s.table_ref && s.table_data) {
        html += renderMiniTable(s.table_data);
      } else if (s.table_ref && typeof loadTableDataForItem === 'function') {
        setTimeout(() => {
          try { loadTableDataForItem(s, () => renderNotePreview(_noteParsedCards)); } catch (_) {}
        }, 0);
      }

      html += `</div>`;
    });

    html += `</div>`;
  });

  // 미리보기 맨 아래 저장 버튼
  html += `
    <div style="display:flex;justify-content:flex-end;margin-top:16px;">
      <button type="button" id="noteSaveBtn"
        style="padding:12px 24px;background:#10b981;color:white;border:none;border-radius:8px;cursor:pointer;font-size:15px;font-weight:600;">
        💾 저장
      </button>
    </div>
  `;
  area.innerHTML = html;
  // 새로 생긴 저장 버튼에 이벤트 바인딩
  const newSaveBtn = area.querySelector('#noteSaveBtn');
  if (newSaveBtn) newSaveBtn.addEventListener('click', noteSave);
  card.style.display = 'block';
}
  window.renderNotePreview = renderNotePreview;




  async function loadTableDataForItem(it, cb) {
    if (!it.table_ref || it._table_loading) return;
    it._table_loading = true;
    try {
      const r = await fetch('/notes/table/' + it.table_ref);
      if (r.ok) {
        const d = await r.json();
        it._table_data = d.table;
      }
    } catch (e) {}
    it._table_loading = false;
    if (cb) cb();
  }

  function showPhotoOverlay(url) {
    document.getElementById('photoOverlayImg').src = url;
    document.getElementById('photoOverlay').classList.add('show');
  }

  async function noteAiParse() {
    const text = document.getElementById('noteRawText').value.trim();
    const status = document.getElementById('noteStatus');
    const saveBtn = document.getElementById('noteSaveBtn');
    if (!text) {
      status.textContent = '⚠️ 텍스트를 입력하세요';
      status.style.color = '#dc2626';
      return;
    }
    status.textContent = '🤖 AI 정리 중...';
    status.style.color = '#6b7280';
    if (saveBtn) { saveBtn.disabled = true; saveBtn.style.opacity = '0.5'; }
    const _divId = document.getElementById('noteDivision').value;
    try {
      const r = await fetch('/admin/notes/ai_parse', {
        method: 'POST',
        credentials: 'same-origin',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text, division_id: _divId }),
      });
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      const data = await r.json();
      _noteParsedCards = data.cards || [];
      window._noteParsedCards = _noteParsedCards;
      renderNotePreview(_noteParsedCards);
      status.textContent = `✅ ${_noteParsedCards.length}개 카드 정리 완료`;
      status.style.color = '#10b981';
      if (saveBtn) { saveBtn.disabled = false; saveBtn.style.opacity = '1'; }
    } catch (e) {
      status.textContent = '❌ AI 정리 실패: ' + e.message;
      status.style.color = '#dc2626';
      _noteParsedCards = null;
    }
  }
  window.noteAiParse = noteAiParse;


  async function noteSave() {
    if (!_noteParsedCards) {
      alert('먼저 AI로 정리해주세요');
      return;
    }
    const divisionId = document.getElementById('noteDivision').value;
    const reportDate = document.getElementById('noteReportDate').value;
    if (!divisionId) { alert('사업부를 선택하세요'); return; }
    if (!reportDate) { alert('보고일자를 선택하세요'); return; }

    const status = document.getElementById('noteStatus');
    status.textContent = '💾 저장 중...';
    status.style.color = '#6b7280';
    try {
      const r = await fetch('/admin/notes', {
        method: 'POST',
        credentials: 'same-origin',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          division_id: divisionId,
          report_date: reportDate,
          raw_text: document.getElementById('noteRawText').value || '',
          cards: _noteParsedCards,
        }),
      });
      if (!r.ok) {
        const err = await r.text();
        throw new Error(err || `HTTP ${r.status}`);
      }
      const data = await r.json();
      status.textContent = `✅ 업로드 완료 (${data.card_count}개 카드)`;
      status.style.color = '#10b981';

      // 미리보기 숨기고 원본 텍스트만 남기기
      _noteParsedCards = null;
      const previewCard = document.getElementById('notePreviewCard');
      const previewArea = document.getElementById('notePreviewArea');
      if (previewArea) previewArea.innerHTML = '';
      if (previewCard) previewCard.style.display = 'none';

      const saveBtn = document.getElementById('noteSaveBtn');
      if (saveBtn) { saveBtn.disabled = true; saveBtn.style.opacity = '0.5'; }
    } catch (e) {
      status.textContent = '❌ 저장 실패: ' + e.message;
      status.style.color = '#dc2626';
    }
  }

  // cards JSON → 텍스트 변환 (편집 가능 포맷)
  function _cardsToText(cards) {
    if (!cards || cards.length === 0) return '';
    const out = [];
    cards.forEach((c, ci) => {
      out.push(`<${c.title || '프로젝트'}>`);
      const sections = Array.isArray(c.sections) ? c.sections : [];
      sections.forEach((s, si) => {
        if (s.title) out.push(`[${s.title}]`);
        const items = Array.isArray(s.items) ? s.items : [];
        // group_id 모아서 } 표기 만들기
        let i = 0;
        while (i < items.length) {
          const it = items[i] || {};
          const gid = it.group_id || '';
          if (gid) {
            // 같은 group_id 연속 묶기
            const group = [];
            let j = i;
            while (j < items.length && (items[j] || {}).group_id === gid) {
              group.push(items[j]);
              j++;
            }
            const normals = group.filter(g => (g.type || '') !== 'group_note');
            const notes = group.filter(g => (g.type || '') === 'group_note');
            normals.forEach((g, idx) => {
              const isLast = idx === normals.length - 1;
              const t = (g.type || 'bullet');
              let prefix = '- ';
              if (t === 'highlight') prefix = '*';
              else if (t === 'sub') prefix = '  → ';
              const tail = (isLast && notes.length > 0) ? ' } ' + notes.map(n => n.text || '').join(', ') : '';
              out.push(prefix + (g.text || '') + tail);
            });
            // 단일 group_note 만 있고 normal 없으면 그냥 출력
            if (normals.length === 0 && notes.length > 0) {
              notes.forEach(n => out.push('} ' + (n.text || '')));
            }
            i = j;
          } else {
            const t = (it.type || 'bullet');
            if (t === 'highlight') out.push('*' + (it.text || ''));
            else if (t === 'sub') out.push('  → ' + (it.text || ''));
            else if (t === 'group_note') out.push('} ' + (it.text || ''));
            else if (t === 'table') out.push('[표]');
            else if (t === 'photo') out.push('[사진]');
            else out.push('- ' + (it.text || ''));
            i++;
          }
        }
      });
      if (ci < cards.length - 1) out.push('');
    });
    return out.join(String.fromCharCode(10));
  }

  async function noteLoadExisting() {
    const divisionId = document.getElementById('noteDivision').value;
    if (!divisionId) { alert('사업부를 먼저 선택하세요'); return; }
    const status = document.getElementById('noteStatus');
    status.textContent = '📥 불러오는 중...';
    status.style.color = '#6b7280';
    try {
      const r = await fetch(`/notes?division_id=${encodeURIComponent(divisionId)}`);
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      const data = await r.json();
      const cards = data.cards || [];
      if (data.report_date) {
        document.getElementById('noteReportDate').value = data.report_date;
      }
      if (cards.length > 0) {
        const txt = _cardsToText(cards);
        const ta = document.getElementById('noteRawText');
        if (ta) ta.value = txt;
        // 미리보기 닫기 (사용자가 텍스트 먼저 보고 수정하도록)
        _noteParsedCards = null;
        const card = document.getElementById('notePreviewCard');
        if (card) card.style.display = 'none';
        status.textContent = `✅ ${cards.length}개 카드를 텍스트로 불러옴 — 수정 후 "🤖 AI 정리" 를 눌러주세요`;
        status.style.color = '#10b981';
      } else {
        status.textContent = '저장된 노트가 없습니다';
        status.style.color = '#6b7280';
      }
    } catch (e) {
      status.textContent = '❌ 불러오기 실패: ' + e.message;
      status.style.color = '#dc2626';
    }
  }

  // ─── 표/사진 첨부 ───
  let _editingTable = null; // {cardIdx, secIdx, itemIdx, headers, rows, title}

  function _getItem(ci, si, ii) {
    if (!_noteParsedCards) return null;
    const c = _noteParsedCards[ci]; if (!c) return null;
    const s = (c.sections || [])[si]; if (!s) return null;
    return (s.items || [])[ii] || null;
  }

  async function openTableModal(ci, si, ii) {
    const it = _getItem(ci, si, ii); if (!it) return;
    let tableData = { title: '', headers: ['구분', '값'], rows: [['', '']] };
    let isExisting = false;
    if (it.table_ref) {
      try {
        const r = await fetch('/notes/table/' + it.table_ref);
        if (r.ok) {
          const d = await r.json();
          tableData = d.table || tableData;
          isExisting = true;
        }
      } catch (e) {}
    }
    _editingTable = {
      ci, si, ii,
      title: tableData.title || '',
      headers: (tableData.headers && tableData.headers.length) ? [...tableData.headers] : ['구분', '값'],
      rows: (tableData.rows && tableData.rows.length) ? tableData.rows.map(r => [...r]) : [['', '']],
    };
    document.getElementById('tableModalTitle').value = _editingTable.title;
    document.getElementById('tablePasteArea').value = '';
    document.getElementById('tableModalDeleteBtn').style.display = isExisting ? 'inline-block' : 'none';
    renderTableEditor();
    document.getElementById('tableModal').classList.add('show');
  }

  function closeTableModal() {
    document.getElementById('tableModal').classList.remove('show');
    _editingTable = null;
  }

  function renderTableEditor() {
    if (!_editingTable) return;
    const area = document.getElementById('tableEditorArea');
    area.innerHTML = '';
    const tbl = document.createElement('table');
    tbl.className = 'modal-table';

    // 헤더 행
    const thead = document.createElement('thead');
    const trh = document.createElement('tr');
    _editingTable.headers.forEach((h, ci) => {
      const th = document.createElement('th');
      const inp = document.createElement('input');
      inp.value = h;
      inp.style.fontWeight = '600';
      inp.style.background = '#f9fafb';
      inp.oninput = (e) => { _editingTable.headers[ci] = e.target.value; };
      th.appendChild(inp);
      trh.appendChild(th);
    });
    thead.appendChild(trh);
    tbl.appendChild(thead);

    // 데이터 행
    const tbody = document.createElement('tbody');
    _editingTable.rows.forEach((row, ri) => {
      const tr = document.createElement('tr');
      _editingTable.headers.forEach((_, ci) => {
        const td = document.createElement('td');
        const inp = document.createElement('input');
        inp.value = row[ci] !== undefined ? row[ci] : '';
        inp.oninput = (e) => {
          while (row.length < _editingTable.headers.length) row.push('');
          row[ci] = e.target.value;
        };
        td.appendChild(inp);
        tr.appendChild(td);
      });
      tbody.appendChild(tr);
    });
    tbl.appendChild(tbody);
    area.appendChild(tbl);
  }

  function addTableRow() {
    if (!_editingTable) return;
    _editingTable.rows.push(_editingTable.headers.map(() => ''));
    renderTableEditor();
  }

  function removeTableRow() {
    if (!_editingTable) return;
    if (_editingTable.rows.length <= 1) { alert('최소 1행은 있어야 합니다'); return; }
    _editingTable.rows.pop();
    renderTableEditor();
  }

  function addTableCol() {
    if (!_editingTable) return;
    _editingTable.headers.push('항목' + (_editingTable.headers.length + 1));
    _editingTable.rows.forEach(r => r.push(''));
    renderTableEditor();
  }

  function removeTableCol() {
    if (!_editingTable) return;
    if (_editingTable.headers.length <= 1) { alert('최소 1열은 있어야 합니다'); return; }
    _editingTable.headers.pop();
    _editingTable.rows.forEach(r => r.pop());
    renderTableEditor();
  }

  // 클립보드 붙여넣기 자동 파싱 (Tab/쉼표)
  document.addEventListener('DOMContentLoaded', () => {
    const pa = document.getElementById('tablePasteArea');
    if (pa) {
      pa.addEventListener('paste', (e) => {
        setTimeout(() => {
          const text = pa.value;
          if (!text.trim() || !_editingTable) return;
          const _LF = String.fromCharCode(10);
          const _CR = String.fromCharCode(13);
          const _TAB = String.fromCharCode(9);
          const _norm = String(text).split(_CR + _LF).join(_LF).split(_CR).join(_LF);
          const lines = _norm.split(_LF).filter(function(l){ return l.trim(); });
          if (lines.length === 0) return;
          const sep = lines[0].indexOf(_TAB) >= 0 ? _TAB : ',';
          const parsed = lines.map(l => l.split(sep).map(c => c.trim()));
          if (parsed.length >= 1) {
            _editingTable.headers = parsed[0];
            _editingTable.rows = parsed.slice(1).length ? parsed.slice(1) : [parsed[0].map(() => '')];
            renderTableEditor();
            pa.value = '';
          }
        }, 50);
      });
    }
  });

  async function saveTableFromModal() {
    if (!_editingTable) return;
    const divisionId = document.getElementById('noteDivision').value;
    if (!divisionId) { alert('사업부를 선택하세요'); return; }
    const it = _getItem(_editingTable.ci, _editingTable.si, _editingTable.ii); if (!it) return;

    const tableData = {
      title: document.getElementById('tableModalTitle').value.trim(),
      headers: _editingTable.headers,
      rows: _editingTable.rows,
    };

    try {
      const body = { division_id: divisionId, table: tableData };
      if (it.table_ref) body.table_ref = it.table_ref;
      const r = await fetch('/admin/notes/table', {
        method: 'POST',
        credentials: 'same-origin',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      if (!r.ok) throw new Error('HTTP ' + r.status);
      const d = await r.json();
      it.table_ref = d.table_ref;
      it._table_data = tableData;
      closeTableModal();
      renderNotePreview(_noteParsedCards);
      // 카드 변경 자동 반영을 위해 노트 저장 권장 메시지
      const st = document.getElementById('noteStatus');
      st.textContent = '✅ 표 저장됨 — 노트 변경사항이 있다면 "💾 저장" 버튼을 눌러주세요';
      st.style.color = '#10b981';
    } catch (e) {
      alert('표 저장 실패: ' + e.message);
    }
  }

  async function deleteTableFromModal() {
    if (!_editingTable) return;
    const it = _getItem(_editingTable.ci, _editingTable.si, _editingTable.ii); if (!it) return;
    if (!it.table_ref) { closeTableModal(); return; }
    if (!confirm('이 표를 삭제하시겠습니까?')) return;
    try {
      const r = await fetch('/admin/notes/table/' + it.table_ref, {
        method: 'DELETE', credentials: 'same-origin',
      });
      // 404여도 클라이언트는 정리
      delete it._table_data;
      delete it.table_ref;
      closeTableModal();
      renderNotePreview(_noteParsedCards);
      const st = document.getElementById('noteStatus');
      st.textContent = '🗑️ 표 삭제됨 — "💾 저장" 버튼을 눌러주세요';
      st.style.color = '#f59e0b';
    } catch (e) {
      alert('표 삭제 실패: ' + e.message);
    }
  }

  // 사진 업로드
  let _pendingPhotoTarget = null; // {ci, si, ii}
  function openPhotoUpload(ci, si, ii) {
    const it = _getItem(ci, si, ii); if (!it) return;
    const divisionId = document.getElementById('noteDivision').value;
    if (!divisionId) { alert('사업부를 선택하세요'); return; }
    _pendingPhotoTarget = { ci, si, ii };
    document.getElementById('notePhotoFileInput').click();
  }

  document.addEventListener('DOMContentLoaded', () => {
    const inp = document.getElementById('notePhotoFileInput');
    if (inp) {
      inp.addEventListener('change', async (e) => {
        const file = e.target.files[0];
        if (!file || !_pendingPhotoTarget) return;
        const { ci, si, ii } = _pendingPhotoTarget;
        const it = _getItem(ci, si, ii);
        const divisionId = document.getElementById('noteDivision').value;
        if (!it || !divisionId) { inp.value = ''; return; }
        const fd = new FormData();
        fd.append('division_id', divisionId);
        fd.append('file', file);
        try {
          const r = await fetch('/admin/notes/photo', {
            method: 'POST', credentials: 'same-origin', body: fd,
          });
          if (!r.ok) throw new Error('HTTP ' + r.status);
          const d = await r.json();
          it.photo_ref = d.photo_ref;
          renderNotePreview(_noteParsedCards);
          const st = document.getElementById('noteStatus');
          st.textContent = '✅ 사진 업로드됨 — "💾 저장" 버튼을 눌러주세요';
          st.style.color = '#10b981';
        } catch (err) {
          alert('사진 업로드 실패: ' + err.message);
        } finally {
          inp.value = '';
          _pendingPhotoTarget = null;
        }
      });
    }
  });

  async function removeNotePhoto(ci, si, ii) {
    const it = _getItem(ci, si, ii); if (!it || !it.photo_ref) return;
    if (!confirm('이 사진을 삭제하시겠습니까?')) return;
    try {
      await fetch('/admin/notes/photo/' + it.photo_ref, {
        method: 'DELETE', credentials: 'same-origin',
      });
    } catch (e) {}
    delete it.photo_ref;
    renderNotePreview(_noteParsedCards);
    const st = document.getElementById('noteStatus');
    st.textContent = '🗑️ 사진 삭제됨 — "💾 저장" 버튼을 눌러주세요';
    st.style.color = '#f59e0b';
  }

  // ─── 매핑 관리 대시보드 ───
  let _mapDivisions = [];
  let _mapActiveDivId = null;
  let _mapReports = [];
  let _mapNotes = {};

  async function initMappingTab() {
    try {
      const divResp = await fetch('/divisions');
      if (!divResp.ok) throw new Error('divisions HTTP ' + divResp.status);
      const divData = await divResp.json();
      _mapDivisions = divData.divisions || [];

      try {
        const r = await fetch('/admin/uploads/history', { credentials: 'same-origin' });
        if (r.ok) {
          const d = await r.json();
          _mapReports = d.items || d.reports || [];
        }
      } catch (e) { _mapReports = []; }

      _mapNotes = {};
      for (const d of _mapDivisions) {
        try {
          const r = await fetch('/notes?division_id=' + encodeURIComponent(d.id));
          if (r.ok) {
            const data = await r.json();
            _mapNotes[d.id] = data;
          }
        } catch (e) {}
      }

      renderMappingChips();
      if (_mapDivisions.length > 0) {
        selectMappingDivision(_mapDivisions[0].id);
      }
    } catch (e) {
      const grid = document.getElementById('mappingProjectGrid');
      if (grid) grid.innerHTML = '<div style="color:#dc2626;padding:16px;">로드 실패: ' + e.message + '</div>';
    }
  }

  function renderMappingChips() {
    const wrap = document.getElementById('mappingDivisionChips');
    if (!wrap) return;
    wrap.innerHTML = '';
    _mapDivisions.forEach(d => {
      const chip = document.createElement('button');
      chip.className = 'map-chip' + (d.id === _mapActiveDivId ? ' active' : '');
      chip.dataset.divId = d.id;
      chip.innerHTML = d.label + '<span class="count">' + (d.projects || []).length + '</span>';
      chip.onclick = () => selectMappingDivision(d.id);
      wrap.appendChild(chip);
    });
  }

  function _countProjectMatches(divisionId, project) {
    let pptCardCount = 0;
    const aliases = (project.aliases || []).map(s => s.toLowerCase());
    const labelLc = (project.label || '').toLowerCase();
    const projectId = project.id;

    for (const rep of _mapReports) {
      const products = rep.products || [];
      for (const p of products) {
        const pkey = p.project_key || p.project || '';
        if (pkey === projectId) { pptCardCount += 1; continue; }
        const text = ((p.name || '') + ' ' + (p.headline || '')).toLowerCase();
        if (labelLc && text.includes(labelLc)) { pptCardCount += 1; continue; }
        for (const al of aliases) {
          if (al && text.includes(al)) { pptCardCount += 1; break; }
        }
      }
    }
    return pptCardCount;
  }

  function selectMappingDivision(divId) {
    _mapActiveDivId = divId;
    renderMappingChips();

    const div = _mapDivisions.find(d => d.id === divId);
    if (!div) return;

    const meta = document.getElementById('mappingDivisionMeta');
    const grid = document.getElementById('mappingProjectGrid');
    const empty = document.getElementById('mappingEmpty');

    const projects = div.projects || [];
    const noteData = _mapNotes[divId] || {};
    const noteCards = noteData.cards || [];

    if (meta) {
      meta.textContent = '▼ ' + div.label + ' — 프로젝트 ' + projects.length + '개 / 주간 보고 카드 ' + noteCards.length + '개';
    }

    if (projects.length === 0) {
      if (grid) grid.innerHTML = '';
      if (empty) empty.style.display = 'block';
      return;
    }
    if (empty) empty.style.display = 'none';

    if (grid) {
      grid.innerHTML = '';
      projects.forEach(prj => {
        const card = document.createElement('div');
        card.className = 'map-pcard';
        card.style.cursor = 'pointer';
        card.onclick = () => openMappingDetail(divId, prj.id);

        const labelLc = (prj.label || '').toLowerCase();
        const noteMatch = noteCards.some(nc => {
          const t = (nc.title || '').toLowerCase();
          return t && (t.includes(labelLc) || labelLc.includes(t));
        });

        const pptCount = _countProjectMatches(divId, prj);

        const pptCls = pptCount > 0 ? 'badge-ppt' : 'badge-empty';
        const noteCls = noteMatch ? 'badge-note' : 'badge-empty';
        const noteText = noteMatch ? '✅' : '—';

        card.innerHTML =
          '<div class="ptitle">' + (prj.label || '?') + '</div>' +
          '<div class="pmeta">' +
            '<span class="' + pptCls + '">📊 PPT ' + pptCount + '</span>' +
            '<span class="' + noteCls + '">📝 노트 ' + noteText + '</span>' +
          '</div>';

        grid.appendChild(card);
      });
    }
  }

  function openMappingDetail(divisionId, projectId) {
    const div = _mapDivisions.find(d => d.id === divisionId);
    if (!div) return;
    const prj = (div.projects || []).find(x => x.id === projectId);
    if (!prj) return;

    document.getElementById('mappingDetailTitle').textContent = prj.label + ' (' + div.label + ')';

    // PPT 카드 매칭
    const aliases = (prj.aliases || []).map(s => s.toLowerCase());
    const labelLc = (prj.label || '').toLowerCase();
    const pptMatches = [];

    for (const rep of _mapReports) {
      const fname = rep.file_name || '';
      const ts = rep.upload_timestamp || '';
      const products = rep.products || [];
      for (const pd of products) {
        const pkey = pd.project_key || pd.project || '';
        const text = ((pd.name || '') + ' ' + (pd.headline || '')).toLowerCase();
        let matched = false;
        if (pkey === projectId) matched = true;
        else if (labelLc && text.includes(labelLc)) matched = true;
        else {
          for (const al of aliases) {
            if (al && text.includes(al)) { matched = true; break; }
          }
        }
        if (matched) {
          pptMatches.push({ rep_file: fname, rep_ts: ts, product: pd });
        }
      }
    }

    // 노트 카드 매칭 (해당 사업부의 노트 중 카드 title이 프로젝트명 포함)
    const noteData = _mapNotes[divisionId] || {};
    const noteCards = noteData.cards || [];
    const noteMatches = noteCards.filter(nc => {
      const t = (nc.title || '').toLowerCase();
      return t && (t.includes(labelLc) || labelLc.includes(t));
    });

    // Subtitle
    const sub = document.getElementById('mappingDetailSubtitle');
    sub.textContent = 'PPT 카드 ' + pptMatches.length + '개 / 노트 카드 ' + noteMatches.length + '개';

    // PPT 영역
    const pptArea = document.getElementById('mappingDetailPpt');
    if (pptMatches.length === 0) {
      pptArea.innerHTML = '<div style="color:#9ca3af;padding:10px 0;">매핑된 PPT 카드가 없습니다.</div>';
    } else {
      pptArea.innerHTML = '';
      pptMatches.forEach(m => {
        const wrap = document.createElement('div');
        wrap.style.cssText = 'background:#f9fafb;border:1px solid #e5e7eb;border-radius:8px;padding:10px 12px;margin-bottom:8px;';
        const fname = m.rep_file || '(파일명 없음)';
        const ts = m.rep_ts ? new Date(m.rep_ts).toLocaleString('ko-KR') : '';
        const name = m.product.name || '';
        const headline = m.product.headline || '';
        const bullets = m.product.summary_bullets || [];

        let html = '<div style="font-size:11px;color:#9ca3af;margin-bottom:4px;">📄 ' + fname + (ts ? ' · ' + ts : '') + '</div>';
        html += '<div style="font-weight:600;color:#1f2937;margin-bottom:2px;">' + (name || '(이름 없음)') + '</div>';
        if (headline) html += '<div style="color:#4b5563;margin-bottom:6px;">' + headline + '</div>';
        if (bullets.length) {
          html += '<ul style="margin:4px 0 0 18px;padding:0;color:#374151;">';
          bullets.forEach(b => { html += '<li style="margin-bottom:2px;">' + b + '</li>'; });
          html += '</ul>';
        }
        wrap.innerHTML = html;
        pptArea.appendChild(wrap);
      });
    }

    // 노트 영역
    const noteArea = document.getElementById('mappingDetailNotes');
    if (noteMatches.length === 0) {
      noteArea.innerHTML = '<div style="color:#9ca3af;padding:10px 0;">매핑된 주간 보고 노트가 없습니다.</div>';
    } else {
      noteArea.innerHTML = '';
      const reportDate = noteData.report_date || '';
      noteMatches.forEach(nc => {
        const wrap = document.createElement('div');
        wrap.style.cssText = 'background:#f0fdf4;border:1px solid #bbf7d0;border-radius:8px;padding:10px 12px;margin-bottom:8px;';
        let html = '<div style="font-weight:600;color:#1E3A5F;margin-bottom:4px;">' + (nc.title || '(제목 없음)') + (reportDate ? ' · ' + reportDate : '') + '</div>';
        (nc.sections || []).forEach(sec => {
          html += '<div style="font-size:12px;font-weight:600;color:#374151;margin:6px 0 2px;padding:3px 8px;background:#dcfce7;border-radius:4px;">' + (sec.title || '') + '</div>';
          (sec.items || []).forEach(it => {
            const isHl = it.type === 'highlight';
            const isSub = it.type === 'sub';
            const dot = isSub ? '↳' : '•';
            const color = isHl ? '#dc2626' : '#1f2937';
            const fw = isHl ? '600' : '400';
            const ml = isSub ? '20px' : '6px';
            html += '<div style="font-size:12px;color:' + color + ';font-weight:' + fw + ';margin-left:' + ml + ';line-height:1.6;">' + dot + ' ' + (it.text || '') + '</div>';
          });
        });
        wrap.innerHTML = html;
        noteArea.appendChild(wrap);
      });
    }

    document.getElementById('mappingDetailModal').classList.add('show');
  }

  function closeMappingDetail() {
    document.getElementById('mappingDetailModal').classList.remove('show');
  }

  let _mapInitialized = false;
  document.addEventListener('DOMContentLoaded', () => {
    document.querySelectorAll('.tab-btn').forEach(btn => {
      if (btn.dataset.tab === 'mapping') {
        btn.addEventListener('click', () => {
          if (!_mapInitialized) {
            _mapInitialized = true;
            initMappingTab();
          }
        });
      }
    });
    // ESC로 모달 닫기
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        const m = document.getElementById('mappingDetailModal');
        if (m && m.classList.contains('show')) m.classList.remove('show');
      }
    });
  });

  // 노트 탭 초기화
  document.addEventListener('DOMContentLoaded', () => {
    initNoteDate();
    loadNoteDivisions();
    const aiBtn = document.getElementById('noteAiParseBtn');
    if (aiBtn) aiBtn.addEventListener('click', noteAiParse);
    const saveBtn = document.getElementById('noteSaveBtn');
    if (saveBtn) saveBtn.addEventListener('click', noteSave);
    const loadBtn = document.getElementById('noteLoadBtn');
    if (loadBtn) loadBtn.addEventListener('click', function(){ if (window.openNoteLoadModal) { window.openNoteLoadModal(); } else { alert('note_loader.js 로딩 실패'); } });
  });

</script>

<!-- 표 편집 모달 -->
<div class="modal-overlay" id="tableModal">
  <div class="modal-box">
    <h3>📊 표 편집</h3>
    <input type="text" id="tableModalTitle" class="modal-input" placeholder="표 제목 (선택)" />
    <div style="font-size:12px;color:#6b7280;margin-bottom:6px;">
      💡 Excel에서 복사한 표를 아래에 붙여넣으면 자동 인식됩니다 (Tab/쉼표 구분).
    </div>
    <textarea id="tablePasteArea" class="modal-input" placeholder="여기에 붙여넣기 → 자동 파싱"></textarea>
    <div id="tableEditorArea"></div>
    <div style="display:flex; gap:6px; margin-bottom:12px;">
      <button onclick="addTableRow()" style="background:#e5e7eb;color:#374151;margin:0;padding:6px 12px;font-size:12px;">＋ 행 추가</button>
      <button onclick="addTableCol()" style="background:#e5e7eb;color:#374151;margin:0;padding:6px 12px;font-size:12px;">＋ 열 추가</button>
      <button onclick="removeTableRow()" style="background:#fee2e2;color:#991b1b;margin:0;padding:6px 12px;font-size:12px;">－ 마지막 행 삭제</button>
      <button onclick="removeTableCol()" style="background:#fee2e2;color:#991b1b;margin:0;padding:6px 12px;font-size:12px;">－ 마지막 열 삭제</button>
    </div>
    <div class="modal-actions">
      <button class="danger" id="tableModalDeleteBtn" onclick="deleteTableFromModal()">🗑️ 삭제</button>
      <button class="cancel" onclick="closeTableModal()">취소</button>
      <button onclick="saveTableFromModal()">💾 저장</button>
    </div>
  </div>
</div>

<!-- 매핑 관리: 프로젝트 상세 모달 -->
<div class="modal-overlay" id="mappingDetailModal">
  <div class="modal-box" style="min-width:600px;max-width:800px;">
    <div style="display:flex;justify-content:space-between;align-items:start;margin-bottom:12px;">
      <h3 id="mappingDetailTitle" style="margin:0;color:#1E3A5F;">프로젝트 상세</h3>
      <button onclick="closeMappingDetail()" style="background:transparent;color:#6b7280;font-size:24px;padding:0;margin:0;border:none;cursor:pointer;line-height:1;">✕</button>
    </div>

    <div style="font-size:13px;color:#6b7280;margin-bottom:14px;" id="mappingDetailSubtitle"></div>

    <h4 style="margin:14px 0 8px;color:#1E3A5F;font-size:15px;">📊 PPT 카드</h4>
    <div id="mappingDetailPpt" style="font-size:13px;"></div>

    <h4 style="margin:18px 0 8px;color:#1E3A5F;font-size:15px;">📝 주간 보고 노트</h4>
    <div id="mappingDetailNotes" style="font-size:13px;"></div>
  </div>
</div>

<!-- PPT 초안 생성 사업부 선택 모달 -->
<div class="modal-overlay" id="draftDivModal">
  <div class="modal-box" style="max-width:520px;">
    <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px;">
      <h3 style="margin:0;">📝 주간 보고 초안 생성</h3>
      <button onclick="closeDraftModal()" style="background:transparent;color:#6b7280;font-size:24px;padding:0;margin:0;border:none;cursor:pointer;line-height:1;">✕</button>
    </div>
    <p style="color:#6b7280;font-size:13px;margin:0 0 10px;"><span id="draftModalFile" style="color:#374151;font-weight:600;"></span></p>
    <p style="color:#6b7280;font-size:13px;margin:0 0 14px;">이 PPT를 어느 사업부 주간 보고로 변환할까요?</p>
    <div id="draftDivChips" style="display:flex;flex-wrap:wrap;gap:8px;margin-bottom:14px;"></div>
    <div id="draftModalStatus" style="font-size:13px;color:#6b7280;margin-top:8px;min-height:18px;"></div>
  </div>
</div>

<!-- 사진 확대 모달 -->
<div class="photo-overlay" id="photoOverlay" onclick="this.classList.remove('show')">
  <img id="photoOverlayImg" src="" alt="확대 사진" />
</div>

<!-- 숨김 사진 업로드 input -->
<input type="file" id="notePhotoFileInput" accept="image/*" style="display:none;" />



<script src="/static/note_loader.js"></script>
<script src="/static/excel_drop.js"></script>
<script src="/static/photo_drop.js"></script>
</body>

</html>
"""

@app.post("/chat")
async def chat(payload: dict):
    """
    RAG 챗봇 엔드포인트
    입력: {"message": "질문 텍스트", "top_k": 5}
    출력: {"answer": "...", "sources": [{project_label, division_id, ...}]}
    """
    message = (payload or {}).get("message", "").strip()
    top_k = int((payload or {}).get("top_k", 5))
    if not message:
        return {"answer": "", "sources": [], "error": "empty message"}

    if not _vs.is_ready():
        return {
            "answer": "챗봇 인덱스가 준비되지 않았어요. 관리자에게 문의해주세요.",
            "sources": [],
            "error": "index_not_ready",
        }

    try:
        hits = _vs.search(message, top_k=top_k)
    except Exception as e:
        return {"answer": "", "sources": [], "error": f"search_failed: {e}"}

    if not hits:
        return {
            "answer": "관련된 프로젝트 정보를 찾지 못했어요.",
            "sources": [],
        }

    context_parts = []
    for i, h in enumerate(hits):
        context_parts.append(
            f"[문서 {i+1}] 사업부: {h.get('division_id')} / "
            f"프로젝트: {h.get('project_label')} / "
            f"보고일: {h.get('report_date')}\n"
            f"{h.get('text','')}"
        )
    context = "\n\n".join(context_parts)

    system_prompt = (
        "너는 반도체 사업부의 프로젝트 보고 어시스턴트다. "
        "주어진 [문서] 내용만을 근거로 사용자의 질문에 한국어로 간결하게 답한다. "
        "규칙: 1) 문서에 없는 내용은 추측하지 말 것 2) 숫자·일정·모델명은 원문 그대로 유지 "
        "3) 3~5문장 이내 4) 마지막에 '(근거: 프로젝트명)' 형태로 인용 표시 "
        "5) 여러 문서를 종합해야 하면 각 문서별 사실만 언급."
    )
    user_prompt = f"[문서]\n{context}\n\n[질문]\n{message}"

    try:
        if client is None:
            return {"answer": "OpenAI 키가 설정되지 않았어요.", "sources": hits}
        resp = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            temperature=0.2,
            max_tokens=500,
        )
        answer = (resp.choices[0].message.content or "").strip()
    except Exception as e:
        return {"answer": "", "sources": hits, "error": f"llm_failed: {e}"}

    return {
        "answer": answer,
        "sources": [
            {
                "division_id": h.get("division_id"),
                "project_label": h.get("project_label"),
                "project_key": h.get("project_key"),
                "report_date": h.get("report_date"),
                "score": round(h.get("score", 0.0), 3),
            }
            for h in hits
        ],
    }



# =========================================================
# KPI 카드: 히스토리 파일 기반 (프로젝트별 월/주차 누적)
# =========================================================
from datetime import datetime, date, timedelta
import calendar as _calendar

KPI_HISTORY_FILE = BASE_DIR / "kpi_history.json" if "BASE_DIR" in globals() else Path("kpi_history.json")


def _load_kpi_history() -> dict:
    """kpi_history.json 로드. 없으면 빈 구조."""
    try:
        with open(KPI_HISTORY_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {"version": 1, "projects": {}}


def _save_kpi_history(data: dict) -> None:
    data["updated_at"] = datetime.utcnow().isoformat() + "Z"
    with open(KPI_HISTORY_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def _iso_week_of(dt: date) -> str:
    """date -> 'YYYY-Wnn'."""
    y, w, _ = dt.isocalendar()
    return f"{y}-W{w:02d}"


def _month_key(dt: date) -> str:
    return f"{dt.year:04d}-{dt.month:02d}"


def _month_label(month_key: str) -> str:
    """'2026-07' -> '7월'."""
    try:
        _, m = month_key.split("-")
        return f"{int(m)}월"
    except Exception:
        return month_key


def _week_label(week_key: str) -> str:
    """'2026-W28' -> 'W28'."""
    try:
        return week_key.split("-")[1]
    except Exception:
        return week_key


def _slice_window(items: dict, key_fn_today, past: int, future: int) -> list:
    """
    items: dict[key -> row], key는 정렬 가능한 문자열
    key_fn_today: 오늘의 기준 key
    past 개 이전 ~ future 개 이후까지 반환. 실제 있는 것만.
    """
    today_key = key_fn_today()
    all_keys = sorted(items.keys())
    if not all_keys:
        return []
    # 오늘 key 앞뒤로 잘라내기 (없으면 가장 가까운 이전 key 기준)
    if today_key in all_keys:
        idx = all_keys.index(today_key)
    else:
        # today_key보다 작거나 같은 가장 마지막 key
        idx = 0
        for i, k in enumerate(all_keys):
            if k <= today_key:
                idx = i
    lo = max(0, idx - past)
    hi = min(len(all_keys), idx + future + 1)
    return [(k, items[k]) for k in all_keys[lo:hi]]


def _build_major_module_kpi_card() -> dict:
    """
    kpi_history.json 기반으로 메이저모듈 KPI 카드 생성.
    - 판가 기준 매출 계산
    - 월: 오늘 기준 직전 1개월(실적) + 향후 2개월 = 최대 3개
    - 주: 오늘 기준 직전 0주 + 향후 4주 = 최대 5개
    """
    hist = _load_kpi_history()
    proj = (hist.get("projects") or {}).get("major_module") or {}
    ue = proj.get("unit_economics") or {
        "EFEM": {"asp": 130000, "material": 107900},
        "VTM":  {"asp": 240000, "material": 196800},
    }
    asp_e = ue.get("EFEM", {}).get("asp", 130000)
    asp_v = ue.get("VTM",  {}).get("asp", 240000)

    def money_10k(efem_qty: float, vtm_qty: float) -> dict:
        efem = efem_qty * asp_e / 10000
        vtm  = vtm_qty  * asp_v / 10000
        return {"efem": round(efem, 2), "vtm": round(vtm, 2), "total": round(efem + vtm, 2)}

    today = date.today()

    months_raw = proj.get("months") or {}
    weeks_raw  = proj.get("weeks")  or {}

    m_slice = _slice_window(months_raw, lambda: _month_key(today), past=1, future=2)
    w_slice = _slice_window(weeks_raw,  lambda: _iso_week_of(today), past=1, future=4)

    months = []
    for mk, row in m_slice:
        e = row.get("efem", 0); v = row.get("vtm", 0)
        months.append({
            "month": _month_label(mk),
            "type": row.get("type", "plan"),
            **money_10k(e, v),
        })

    weeks = []
    for wk, row in w_slice:
        e = row.get("efem", 0); v = row.get("vtm", 0)
        weeks.append({
            "week": _week_label(wk),
            "type": row.get("type", "plan"),
            **money_10k(e, v),
        })

    # 주차별 타이틀 (가장 이른 주가 속한 달 표시)
    week_group_label = ""
    if w_slice:
        first_wk = w_slice[0][0]
        try:
            y, wn = first_wk.split("-W")
            monday = datetime.strptime(f"{y} {int(wn)} 1", "%G %V %u").date()
            week_group_label = f"{monday.month}월 주차별"
        except Exception:
            week_group_label = "주차별"

    return {
        "title": "월별/주차별 매출",
        "metric_mode": "revenue",
        "metric_note": "판가 기준 매출",
        "unit_label": "만불",
        "unit_economics": {
            "EFEM": {"asp": asp_e, "material": ue.get("EFEM", {}).get("material", 0)},
            "VTM":  {"asp": asp_v, "material": ue.get("VTM",  {}).get("material", 0)},
        },
        "week_group_label": week_group_label,
        "months": months,
        "weeks": weeks,
        "footnotes": [
            "※ 단위: 만불 (USD 10K)",
            "※ 매출 = 수량 × 판가 (ASP 기준)",
        ],
    }


def _build_major_module_issue_lines() -> list:
    """kpi_history.json 에서 이슈 라인 로드. 없으면 빈 리스트."""
    hist = _load_kpi_history()
    proj = (hist.get("projects") or {}).get("major_module") or {}
    return proj.get("issue_lines") or []


# =========================================================
# KPI 관리 API (Phase 2): 월/주차/이슈 라인 upsert
# =========================================================
from pydantic import BaseModel


class KpiMonthPayload(BaseModel):
    month: str            # "2026-07"
    efem: float
    vtm: float
    type: str = "plan"    # "actual" | "plan"
    source: str = ""


class KpiWeekPayload(BaseModel):
    week: str             # "2026-W28"
    efem: float
    vtm: float
    type: str = "plan"
    source: str = ""


class KpiIssueLinesPayload(BaseModel):
    issue_lines: list


def _ensure_project(hist: dict, project_key: str) -> dict:
    hist.setdefault("projects", {})
    proj = hist["projects"].setdefault(project_key, {
        "unit_economics": {},
        "months": {},
        "weeks": {},
        "issue_lines": [],
    })
    proj.setdefault("months", {})
    proj.setdefault("weeks", {})
    proj.setdefault("issue_lines", [])
    return proj


def _should_overwrite(existing: dict, incoming_type: str) -> bool:
    """
    같은 key가 이미 있을 때 덮어쓸지 판단.
    - existing이 없으면 True
    - actual > plan (actual이 들어오면 무조건 덮음)
    - 같은 type이면 최신 upload가 덮음 (True)
    """
    if not existing:
        return True
    et = existing.get("type", "plan")
    if incoming_type == "actual" and et == "plan":
        return True
    if incoming_type == "plan" and et == "actual":
        return False
    return True  # 같은 type이면 최신이 덮음


@app.get("/admin/kpi/{project_key}")
def admin_kpi_get(project_key: str, _exp: int = Depends(get_admin_session)):
    hist = _load_kpi_history()
    proj = (hist.get("projects") or {}).get(project_key)
    if not proj:
        return {"project_key": project_key, "months": {}, "weeks": {}, "issue_lines": []}
    return {"project_key": project_key, **proj}


@app.post("/admin/kpi/{project_key}/months")
def admin_kpi_upsert_month(
    project_key: str,
    payload: KpiMonthPayload,
    _exp: int = Depends(get_admin_session),
):
    hist = _load_kpi_history()
    proj = _ensure_project(hist, project_key)
    existing = proj["months"].get(payload.month)
    if not _should_overwrite(existing, payload.type):
        return {"status": "skipped", "reason": "existing actual not overwritten by plan", "month": payload.month}
    proj["months"][payload.month] = {
        "efem": payload.efem,
        "vtm": payload.vtm,
        "type": payload.type,
        "source": payload.source,
        "uploaded_at": datetime.utcnow().isoformat() + "Z",
    }
    _save_kpi_history(hist)
    return {"status": "ok", "month": payload.month, "row": proj["months"][payload.month]}


@app.post("/admin/kpi/{project_key}/weeks")
def admin_kpi_upsert_week(
    project_key: str,
    payload: KpiWeekPayload,
    _exp: int = Depends(get_admin_session),
):
    hist = _load_kpi_history()
    proj = _ensure_project(hist, project_key)
    existing = proj["weeks"].get(payload.week)
    if not _should_overwrite(existing, payload.type):
        return {"status": "skipped", "reason": "existing actual not overwritten by plan", "week": payload.week}
    proj["weeks"][payload.week] = {
        "efem": payload.efem,
        "vtm": payload.vtm,
        "type": payload.type,
        "source": payload.source,
        "uploaded_at": datetime.utcnow().isoformat() + "Z",
    }
    _save_kpi_history(hist)
    return {"status": "ok", "week": payload.week, "row": proj["weeks"][payload.week]}


@app.post("/admin/kpi/{project_key}/issue_lines")
def admin_kpi_replace_issue_lines(
    project_key: str,
    payload: KpiIssueLinesPayload,
    _exp: int = Depends(get_admin_session),
):
    hist = _load_kpi_history()
    proj = _ensure_project(hist, project_key)
    proj["issue_lines"] = payload.issue_lines
    _save_kpi_history(hist)
    return {"status": "ok", "count": len(payload.issue_lines)}
