"""
사업부 진행현황 보고 - 백엔드 메인
- PPT 업로드 → 슬라이드 PNG 변환 → GPT-4o 요약 → 신호등 분류
- 사용자 직접 차트/사진 업로드 및 부서·섹션 매핑
- 프로젝트별 상세 API 제공
"""
import os
import json
import shutil
import hashlib
import subprocess
from datetime import datetime, timedelta
from pathlib import Path

from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse
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

        division_id = _cl.derive_division_from_project(project_id)

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
SLIDES_DIR = DATA_DIR / "slides"
SLIDE_IMAGES_DIR = DATA_DIR / "slide_images"   # 기존 호환용
CROPPED_DIR = DATA_DIR / "cropped"
CUSTOM_IMAGES_DIR = DATA_DIR / "custom_images"
LATEST_FILE = DATA_DIR / "reports_latest.json"
HISTORY_FILE = DATA_DIR / "reports_history.json"
IMAGE_MAPPINGS_FILE = DATA_DIR / "image_mappings.json"

for d in [UPLOAD_DIR, SLIDES_DIR, SLIDE_IMAGES_DIR, CROPPED_DIR, CUSTOM_IMAGES_DIR]:
    d.mkdir(exist_ok=True)

if not IMAGE_MAPPINGS_FILE.exists():
    IMAGE_MAPPINGS_FILE.write_text('{"images": []}', encoding="utf-8")

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
app.mount("/custom_images", StaticFiles(directory=str(CUSTOM_IMAGES_DIR)), name="custom_images")


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

def _load_image_mappings():
    return _read_json(IMAGE_MAPPINGS_FILE, {"images": []})


def _save_image_mappings(data):
    _write_json(IMAGE_MAPPINGS_FILE, data)


# =========================================================
# 1. 헬스체크
# =========================================================
@app.get("/health")
def health():
    return {"status": "ok", "time": datetime.now().isoformat()}


# =========================================================
# 2. PPT 업로드
# =========================================================
@app.post("/upload")
async def upload_ppt(
    file: UploadFile = File(...),
    password: str = Form(...),
    report_family: str = Form("default"),
):
    if password != UPLOAD_PASSWORD:
        raise HTTPException(status_code=401, detail="비밀번호가 틀립니다.")
    if not file.filename.lower().endswith(".pptx"):
        raise HTTPException(status_code=400, detail=".pptx 파일만 업로드 가능합니다.")

    _cleanup_old_files()

    doc_id = _make_doc_id(file.filename)
    saved_pptx_path = UPLOAD_DIR / f"{doc_id}.pptx"
    with open(saved_pptx_path, "wb") as f:
        shutil.copyfileobj(file.file, f)

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
    return {"cards": cards}

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
@app.post("/custom_image/upload")
async def upload_custom_image(
    file: UploadFile = File(...),
    project_key: str = Form(...),
    section_title: str = Form(...),
    caption: str = Form(""),
):
    """차트/사진 직접 업로드 후 부서+섹션에 매핑"""
    ext = Path(file.filename).suffix.lower()
    if ext not in [".png", ".jpg", ".jpeg", ".gif", ".webp"]:
        raise HTTPException(status_code=400, detail="이미지 파일만 업로드 가능합니다.")

    ts = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    safe_name = f"{ts}{ext}"
    save_path = CUSTOM_IMAGES_DIR / safe_name
    with open(save_path, "wb") as f:
        shutil.copyfileobj(file.file, f)

    mappings = _load_image_mappings()
    new_entry = {
        "id": ts,
        "filename": safe_name,
        "url": f"/custom_images/{safe_name}",
        "project_key": project_key,
        "section_title": section_title,
        "caption": caption,
        "uploaded_at": datetime.now().isoformat(),
        "original_name": file.filename,
    }
    mappings.setdefault("images", []).append(new_entry)
    _save_image_mappings(mappings)

    return {"ok": True, "image": new_entry}


@app.get("/custom_image/list")
def list_custom_images(project_key: str = None):
    """등록된 이미지 목록"""
    mappings = _load_image_mappings()
    images = mappings.get("images", [])
    if project_key:
        images = [img for img in images if img.get("project_key") == project_key]
    return {"images": images}


@app.delete("/custom_image/{image_id}")
def delete_custom_image(image_id: str):
    """이미지 삭제"""
    mappings = _load_image_mappings()
    images = mappings.get("images", [])
    target = next((img for img in images if img.get("id") == image_id), None)
    if not target:
        raise HTTPException(status_code=404, detail="이미지를 찾을 수 없습니다.")

    try:
        (CUSTOM_IMAGES_DIR / target["filename"]).unlink()
    except Exception:
        pass

    mappings["images"] = [img for img in images if img.get("id") != image_id]
    _save_image_mappings(mappings)
    return {"ok": True}


# =========================================================
# 6. 어드민 페이지 (브라우저용)
# =========================================================
@app.get("/admin/upload", response_class=HTMLResponse)
def admin_upload_page():
    return HTMLResponse(content=_ADMIN_UPLOAD_HTML)


@app.post("/admin/reset")
def admin_reset(password: str = Form(...)):
    if password != UPLOAD_PASSWORD:
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
<title>차트/사진 업로드 관리</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; max-width: 900px; margin: 40px auto; padding: 0 20px; background: #f5f5f7; color: #1d1d1f; }
  h1 { margin-bottom: 24px; }
  h2 { margin-top: 0; font-size: 18px; }
  .card { background: white; padding: 24px; border-radius: 12px; margin-bottom: 20px; box-shadow: 0 2px 8px rgba(0,0,0,0.05); }
  label { display: block; margin: 14px 0 6px; font-weight: 600; font-size: 13px; color: #333; }
  input, select { width: 100%; padding: 10px; border: 1px solid #ddd; border-radius: 8px; font-size: 14px; box-sizing: border-box; background: white; }
  button { background: #007aff; color: white; border: none; padding: 12px 24px; border-radius: 8px; font-size: 15px; font-weight: 600; cursor: pointer; margin-top: 16px; }
  button:hover { background: #0051d5; }
  button.delete { background: #ff3b30; padding: 6px 12px; font-size: 13px; margin-top: 0; }
  .image-item { display: flex; align-items: center; gap: 16px; padding: 12px; border-bottom: 1px solid #eee; }
  .image-item:last-child { border-bottom: none; }
  .image-item img { width: 80px; height: 60px; object-fit: cover; border-radius: 6px; border: 1px solid #ddd; }
  .image-info { flex: 1; }
  .image-info b { display: block; margin: 4px 0; }
  .image-info small { color: #888; }
  .badge { display: inline-block; padding: 3px 10px; background: #e8f0fe; color: #1967d2; border-radius: 12px; font-size: 12px; margin-right: 6px; }
  .badge.section { background: #fff3cd; color: #856404; }
  .success { color: #34c759; margin-top: 12px; font-weight: 600; }
  .error { color: #ff3b30; margin-top: 12px; font-weight: 600; }
  .empty { color: #888; text-align: center; padding: 30px; }
</style>
</head>
<body>
<h1>📊 차트/사진 업로드 관리</h1>

<div class="card">
  <h2>📤 새 이미지 업로드</h2>
  <form id="uploadForm">
    <label>이미지 파일 (PNG, JPG, GIF, WebP)</label>
    <input type="file" id="fileInput" accept="image/*" required>

    <label>부서 (프로젝트)</label>
    <select id="projectKey" required>
      <option value="">선택하세요...</option>
    </select>

    <label>섹션</label>
    <select id="sectionTitle" required>
      <option value="양산">양산</option>
      <option value="개발">개발</option>
      <option value="EMA">EMA</option>
      <option value="주차별 출하실적 및 계획">주차별 출하실적 및 계획</option>
      <option value="다음 액션">다음 액션</option>
    </select>

    <label>설명 (선택)</label>
    <input type="text" id="caption" placeholder="예: 개발 모델 진행 현황">

    <button type="submit">📤 업로드</button>
    <div id="uploadMsg"></div>
  </form>
</div>

<div class="card">
  <h2>📋 등록된 이미지</h2>
  <div id="imageList">로딩 중...</div>
</div>

<script>
  async function loadProjects() {
    const res = await fetch('/projects');
    const data = await res.json();
    const sel = document.getElementById('projectKey');
    sel.innerHTML = '<option value="">선택하세요...</option>';
    data.projects.forEach(p => {
      const opt = document.createElement('option');
      opt.value = p.key;
      const statusIcon = p.status === 'RED' ? '🔴' : (p.status === 'BLUE' ? '🔵' : '⚫');
      opt.textContent = statusIcon + ' ' + p.label;
      sel.appendChild(opt);
    });
  }

  async function loadImages() {
    const res = await fetch('/custom_image/list');
    const data = await res.json();
    const list = document.getElementById('imageList');
    if (!data.images.length) {
      list.innerHTML = '<p class="empty">등록된 이미지가 없습니다.</p>';
      return;
    }
    list.innerHTML = data.images.map(img => `
      <div class="image-item">
        <img src="${img.url}" alt="">
        <div class="image-info">
          <span class="badge">${img.project_key}</span>
          <span class="badge section">${img.section_title}</span>
          <b>${img.caption || img.original_name}</b>
          <small>${new Date(img.uploaded_at).toLocaleString('ko-KR')}</small>
        </div>
        <button class="delete" onclick="deleteImg('${img.id}')">삭제</button>
      </div>
    `).join('');
  }

  async function deleteImg(id) {
    if (!confirm('정말 삭제할까요?')) return;
    await fetch('/custom_image/' + id, { method: 'DELETE' });
    loadImages();
  }

  document.getElementById('uploadForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    const fd = new FormData();
    fd.append('file', document.getElementById('fileInput').files[0]);
    fd.append('project_key', document.getElementById('projectKey').value);
    fd.append('section_title', document.getElementById('sectionTitle').value);
    fd.append('caption', document.getElementById('caption').value);

    const msg = document.getElementById('uploadMsg');
    msg.textContent = '⏳ 업로드 중...';
    msg.className = '';

    try {
      const res = await fetch('/custom_image/upload', { method: 'POST', body: fd });
      const data = await res.json();
      if (data.ok) {
        msg.textContent = '✅ 업로드 완료!';
        msg.className = 'success';
        document.getElementById('uploadForm').reset();
        loadImages();
      } else {
        throw new Error(data.detail || 'unknown');
      }
    } catch (err) {
      msg.textContent = '❌ ' + err.message;
      msg.className = 'error';
    }
  });

  loadProjects();
  loadImages();
</script>
</body>
</html>
"""