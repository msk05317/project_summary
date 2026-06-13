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

    severity = {"RED": 3, "BLUE": 2, "BLACK": 1}
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
1. <텍스트>로 감싼 것은 새 카드(프로젝트 그룹)
2. 1. 2. 같은 번호는 카드 내부의 섹션
3. 1) 2) 같은 들여쓰기 된 번호는 일반 항목(bullet)으로 처리. 별도 섹션으로 분리 금지
4. *로 시작하는 줄, 빨간색 강조하면 좋은 핵심 정보는 type: highlight
5. -, ▸ 일반 항목은 type: bullet
6. →, =>, 또는 들여쓰기 된 내용은 type: sub
6-1. } 또는 ←, ⟵ 기호 뒤에 있는 메모는 바로 위 여러 항목에 공통 적용되는 메모입니다. 다음과 같이 처리하세요:
    - 묶음 대상 항목들에 동일한 "group_id": "g1", "g2"... 부여
    - 공통 메모 자체는 {"type": "group_note", "text": "...", "group_id": "g1"} 로 추가
    - group_id는 카드(프로젝트) 단위로 g1부터 시작
7. 카드 제목·섹션 제목에서 번호 제거
8. 항목 텍스트에서 선행 기호 제거 (-, *, ▸). 단, 본문 안의 → 같은 화살표는 유지
9. 의미는 절대 바꾸지 말 것
10. 빈 항목·중복 항목은 만들지 말 것

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


@app.post("/admin/notes/ai_parse")
def admin_notes_ai_parse(payload: dict, _admin: int = Depends(get_admin_session)):
    """자유 형식 텍스트를 AI로 구조화 JSON으로 변환 (증분 병합 지원)."""
    text = (payload or {}).get("text", "").strip()
    division_id = (payload or {}).get("division_id", "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="text가 비어있습니다")

    existing_cards = []
    if division_id:
        data = _load_notes()
        existing = data.get("notes", {}).get(division_id, {})
        existing_cards = existing.get("cards", []) or []

    existing_json = json.dumps({"cards": existing_cards}, ensure_ascii=False)
    user_message = (
        f"[기존 노트 JSON]\n{existing_json}\n\n"
        f"[이번 주 변경/추가 텍스트]\n{text}\n\n"
        "위 기존 노트에 이번 주 변경을 병합한 최종 JSON을 출력해 주세요."
    )

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
        return json.loads(content)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"AI 파싱 실패: {str(e)}")


@app.post("/admin/notes")
def admin_save_note(payload: dict, _admin: int = Depends(get_admin_session)):
    """사업부별 노트 저장."""
    division_id = (payload or {}).get("division_id", "").strip()
    report_date = (payload or {}).get("report_date", "").strip()
    cards = (payload or {}).get("cards", [])

    if not division_id:
        raise HTTPException(status_code=400, detail="division_id 필수")
    if not isinstance(cards, list):
        raise HTTPException(status_code=400, detail="cards는 배열이어야 합니다")

    from datetime import datetime
    data = _load_notes()
    data.setdefault("notes", {})[division_id] = {
        "report_date": report_date,
        "updated_at": datetime.now().isoformat(),
        "cards": cards,
    }
    _save_notes(data)
    return {"ok": True, "division_id": division_id, "card_count": len(cards)}


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
        raise HTTPException(status_code=404, detail="프로젝트를 찾을 수 없습니다.")
    
    # 🟢 프로젝트 상세 enrichment (기존 필드 변경 없음)
    detail = enrich_project_detail(detail)

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
        <button type="button" id="noteSaveBtn" disabled style="padding:10px 18px;background:#10b981;color:white;border:none;border-radius:6px;cursor:pointer;font-size:14px;font-weight:500;opacity:0.5;">💾 저장</button>
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

  function renderNotePreview(cards) {
    const area = document.getElementById('notePreviewArea');
    const card = document.getElementById('notePreviewCard');
    if (!area || !card) return;
    card.style.display = 'block';
    area.innerHTML = '';

    if (!cards || cards.length === 0) {
      area.innerHTML = '<div style="color:#9ca3af;padding:24px;text-align:center;">표시할 내용이 없습니다</div>';
      return;
    }

    cards.forEach((c, ci) => {
      const wrap = document.createElement('div');
      wrap.style.cssText = 'background:white;border-radius:12px;padding:16px;margin-bottom:14px;box-shadow:0 1px 3px rgba(0,0,0,0.05);';

      const title = document.createElement('div');
      title.style.cssText = 'font-size:18px;font-weight:700;color:#1E3A5F;margin-bottom:12px;';
      title.textContent = c.title || '';
      wrap.appendChild(title);

      (c.sections || []).forEach((sec, si) => {
        const secTitle = document.createElement('div');
        secTitle.style.cssText = 'font-size:15px;font-weight:600;color:#374151;margin:10px 0 6px;padding:6px 10px;background:#f3f4f6;border-radius:6px;';
        secTitle.textContent = sec.title || '';
        wrap.appendChild(secTitle);

        (sec.items || []).forEach((it, ii) => {
          const isHighlight = it.type === 'highlight';
          const isSub = it.type === 'sub';
          const padLeft = isSub ? 28 : 12;
          const hasTable = !!it.table_ref;
          const hasPhoto = !!it.photo_ref;

          const row = document.createElement('div');
          row.className = 'note-item-row';
          row.style.cssText = `font-size:13px;line-height:1.6;padding:3px 0 3px ${padLeft}px;color:${isHighlight ? '#dc2626' : '#1f2937'};${isHighlight ? 'font-weight:600;' : ''}`;

          const textSpan = document.createElement('span');
          textSpan.className = 'note-item-text';
          const dot = isSub ? '↳' : '•';
          textSpan.textContent = `${dot} ${it.text || ''}`;
          row.appendChild(textSpan);

          const tblBtn = document.createElement('button');
          tblBtn.className = 'note-attach-btn' + (hasTable ? ' has-attachment' : '');
          tblBtn.textContent = hasTable ? '📊 표' : '📊';
          tblBtn.title = '표 첨부/편집';
          tblBtn.onclick = () => openTableModal(ci, si, ii);
          row.appendChild(tblBtn);

          const photoBtn = document.createElement('button');
          photoBtn.className = 'note-attach-btn' + (hasPhoto ? ' has-attachment' : '');
          photoBtn.textContent = hasPhoto ? '📷 사진' : '📷';
          photoBtn.title = '사진 첨부';
          photoBtn.onclick = () => openPhotoUpload(ci, si, ii);
          row.appendChild(photoBtn);

          wrap.appendChild(row);

          // 표 미니 프리뷰
          if (hasTable && it._table_data) {
            const t = it._table_data;
            const tbl = document.createElement('table');
            tbl.className = 'note-mini-table';
            if (t.title) {
              const cap = document.createElement('caption');
              cap.textContent = t.title;
              cap.style.cssText = 'caption-side:top;text-align:left;font-size:11px;color:#6b7280;padding:2px 0;';
              tbl.appendChild(cap);
            }
            if ((t.headers || []).length) {
              const thead = document.createElement('thead');
              const trh = document.createElement('tr');
              t.headers.forEach(h => { const th = document.createElement('th'); th.textContent = h; trh.appendChild(th); });
              thead.appendChild(trh); tbl.appendChild(thead);
            }
            const tbody = document.createElement('tbody');
            (t.rows || []).forEach(r => {
              const tr = document.createElement('tr');
              r.forEach(cell => { const td = document.createElement('td'); td.textContent = cell; tr.appendChild(td); });
              tbody.appendChild(tr);
            });
            tbl.appendChild(tbody);
            wrap.appendChild(tbl);
          } else if (hasTable && !it._table_data) {
            // 표는 있지만 데이터 미로드 → 비동기 로드
            loadTableDataForItem(it, () => renderNotePreview(_noteParsedCards));
          }

          // 사진 미니 프리뷰
          if (hasPhoto) {
            const img = document.createElement('img');
            img.className = 'note-mini-photo';
            img.src = '/note_photos/' + it.photo_ref;
            img.onclick = () => showPhotoOverlay(img.src);
            wrap.appendChild(img);
            const ctrl = document.createElement('div');
            ctrl.className = 'note-attach-controls';
            const delBtn = document.createElement('button');
            delBtn.className = 'danger';
            delBtn.textContent = '사진 삭제';
            delBtn.onclick = () => removeNotePhoto(ci, si, ii);
            ctrl.appendChild(delBtn);
            wrap.appendChild(ctrl);
          }
        });
      });

      area.appendChild(wrap);
    });
  }

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
    saveBtn.disabled = true;
    saveBtn.style.opacity = '0.5';
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
      renderNotePreview(_noteParsedCards);
      status.textContent = `✅ ${_noteParsedCards.length}개 카드 정리 완료`;
      status.style.color = '#10b981';
      saveBtn.disabled = false;
      saveBtn.style.opacity = '1';
    } catch (e) {
      status.textContent = '❌ AI 정리 실패: ' + e.message;
      status.style.color = '#dc2626';
      _noteParsedCards = null;
    }
  }

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
          cards: _noteParsedCards,
        }),
      });
      if (!r.ok) {
        const err = await r.text();
        throw new Error(err || `HTTP ${r.status}`);
      }
      const data = await r.json();
      status.textContent = `✅ 저장 완료 (${data.card_count}개 카드)`;
      status.style.color = '#10b981';
    } catch (e) {
      status.textContent = '❌ 저장 실패: ' + e.message;
      status.style.color = '#dc2626';
    }
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
      _noteParsedCards = data.cards || [];
      if (data.report_date) {
        document.getElementById('noteReportDate').value = data.report_date;
      }
      if (_noteParsedCards.length > 0) {
        renderNotePreview(_noteParsedCards);
        document.getElementById('noteSaveBtn').disabled = false;
        document.getElementById('noteSaveBtn').style.opacity = '1';
        status.textContent = `✅ 기존 노트 ${_noteParsedCards.length}개 카드 불러옴`;
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
    if (loadBtn) loadBtn.addEventListener('click', noteLoadExisting);
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

</body>

</html>
"""