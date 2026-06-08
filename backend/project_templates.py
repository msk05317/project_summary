"""
프로젝트(부서) 단위 보기 모듈
- GPT가 자동 정리한 sections를 그대로 사용
- 프로젝트 리스트는 고정, 키워드로 자동 매핑
- 섹션 이미지 매칭은 '부분 매칭' 방식 (admin 업로드 섹션명이 GPT 섹션명과 달라도 매칭됨)
"""
import json
import re
from pathlib import Path

BASE_DIR = Path(__file__).parent
import os
DATA_DIR = Path(os.getenv("DATA_DIR", str(BASE_DIR)))

MANUAL_OVERRIDES_FILE = DATA_DIR / "manual_overrides.json"
CUSTOM_IMAGES_MAPPING_FILE = DATA_DIR / "image_mappings.json"

# 1. 프로젝트 라벨 (8개 고정)
PROJECT_LABELS = {
    "chamber": "챔버",
    "havaplate": "하바플레이트",
    "enclosure": "엔클로저",
    "casting_enclosure": "캐스팅 엔클로저",
    "cup": "CUP",
    "powerbox": "파워박스",
    "major_module": "메이저모듈",
    "frame": "프레임",
}

# 2. 키워드 → 프로젝트 매핑 (구체적인 키워드 우선)
PRODUCT_TO_PROJECT = [
    (["캐스팅 엔클로저", "캐스팅엔클로저", "casting enclosure", "캐스팅"], "casting_enclosure"),
    (["엔클로저", "enclosure"], "enclosure"),
    (["챔버", "chamber", "메탈챔버", "메탈 챔버", "dep 챔버", "dep챔버"], "chamber"),
    (["하바플레이트", "하바 플레이트", "하바", "havaplate", "hava plate"], "havaplate"),
    (["cup", "컵"], "cup"),
    (["파워박스", "powerbox", "power box", "aether gdx", "aether", "에테르",
      "mach i", "mach 1", "machi"], "powerbox"),
    (["메이저모듈", "메이저 모듈", "major module", "메이져모듈", "메이져 모듈",
      "efem", "vtm", "텍슨", "긴급 신규"], "major_module"),
    (["프레임", "frame", "내재화프레임", "내재화 프레임",
      "cefem", "treos", "quaros", "faraday", "직납프레임", "직납"], "frame"),
]


def _match_project_key(product_name: str) -> str | None:
    if not product_name:
        return None
    name = product_name.lower()
    for keywords, key in PRODUCT_TO_PROJECT:
        for kw in keywords:
            if kw.lower() in name:
                return key
    return None


# 3. 외부 파일 로더
def load_manual_overrides() -> dict:
    if MANUAL_OVERRIDES_FILE.exists():
        try:
            return json.loads(MANUAL_OVERRIDES_FILE.read_text(encoding="utf-8"))
        except Exception:
            return {}
    return {}


# ✨ 섹션 제목 정규화 (공백/특수문자 제거, 소문자화)
def _normalize_title(s: str) -> str:
    if not s:
        return ""
    # 공백, 특수문자 제거 + 소문자
    return re.sub(r"[\s\-_/()\[\]&,.·]+", "", s).lower()


# ✨ 섹션 제목에서 의미 있는 키워드 추출
_STOP_WORDS = {"및", "의", "에", "을", "를", "은", "는", "이", "가", "와", "과",
               "현황", "상황", "내용", "관련", "기타", "에서", "에는", "에도"}


def _extract_keywords(title: str) -> set[str]:
    """섹션 제목에서 의미 있는 키워드만 뽑기 (한글 2자 이상, 영문 3자 이상)"""
    if not title:
        return set()
    # 한글 단어 / 영문 단어 분리
    tokens = re.findall(r"[가-힣]{2,}|[A-Za-z]{3,}", title)
    return {t for t in tokens if t not in _STOP_WORDS}


def _section_match_score(upload_title: str, gpt_title: str) -> float:
    """
    업로드 섹션명과 GPT 섹션명의 매칭 점수 (0.0 ~ 1.0)
    - 1.0: 완전 일치 (정규화 후)
    - 0.5 이상: 키워드 일부 일치
    - 0.0: 매칭 없음
    """
    if not upload_title or not gpt_title:
        return 0.0

    # 1단계: 정규화 후 완전 일치
    if _normalize_title(upload_title) == _normalize_title(gpt_title):
        return 1.0

    # 2단계: 한쪽이 다른 쪽 포함
    n_up = _normalize_title(upload_title)
    n_gpt = _normalize_title(gpt_title)
    if n_up and n_gpt and (n_up in n_gpt or n_gpt in n_up):
        return 0.9

    # 3단계: 키워드 교집합
    up_kw = _extract_keywords(upload_title)
    gpt_kw = _extract_keywords(gpt_title)
    if not up_kw or not gpt_kw:
        return 0.0

    intersection = up_kw & gpt_kw
    if not intersection:
        return 0.0

    # 교집합 / 둘 중 작은 쪽 크기
    score = len(intersection) / min(len(up_kw), len(gpt_kw))
    return score


def _load_custom_images_for_section(project_key: str, section_title: str) -> list[dict]:
    """
    이미지 매핑에서 해당 프로젝트 + 섹션에 가장 잘 매칭되는 이미지 반환
    - 완전 일치 우선
    - 그 다음 부분 일치 (점수 0.5 이상)
    """
    if not CUSTOM_IMAGES_MAPPING_FILE.exists():
        return []
    try:
        data = json.loads(CUSTOM_IMAGES_MAPPING_FILE.read_text(encoding="utf-8"))
    except Exception:
        return []

    # 같은 프로젝트의 이미지만 우선 필터
    project_imgs = [
        img for img in data.get("images", [])
        if img.get("project_key") == project_key
    ]
    if not project_imgs:
        return []

    # 점수 매기기
    scored = []
    for img in project_imgs:
        score = _section_match_score(img.get("section_title", ""), section_title)
        if score >= 0.5:  # 임계값
            scored.append((score, img))

    # 점수 높은 순 정렬
    scored.sort(key=lambda x: x[0], reverse=True)
    return [img for _, img in scored]


# 4. 신호등 우선순위
def _status_priority(status: str) -> int:
    return {"RED": 3, "BLUE": 2, "BLACK": 1}.get(status, 0)


def _worst_status(a: str, b: str) -> str:
    return a if _status_priority(a) >= _status_priority(b) else b


# 5. 보고서 → 프로젝트별 그룹화
def aggregate_projects(reports_latest: list[dict]) -> dict:
    grouped: dict[str, dict] = {}
    for report in reports_latest:
        report_date = report.get("report_meta", {}).get("date") or report.get("report_date")
        doc_id = report.get("doc_id", "")
        for product in report.get("products", []):
            product_name = product.get("name") or product.get("product", "")
            category = product.get("category", "")
            key = _match_project_key(product_name) or _match_project_key(category)
            if not key:
                print(f"⚠️  매핑 실패: name='{product_name}' category='{category}'")
                continue
            status = product.get("status", "BLACK")
            label = PROJECT_LABELS.get(key, product_name)
            if key not in grouped:
                grouped[key] = {
                    "label": label,
                    "status": status,
                    "report_date": report_date,
                    "doc_id": doc_id,
                    "header_summary": product.get("header_summary", ""),
                    "gpt_sections": [],
                }
            else:
                grouped[key]["status"] = _worst_status(grouped[key]["status"], status)
                if product.get("header_summary"):
                    grouped[key]["header_summary"] = product["header_summary"]
            for sec in (product.get("sections") or []):
                grouped[key]["gpt_sections"].append(sec)
    return grouped


# 6. 프로젝트 상세 응답 생성
def build_project_detail(project_key: str, grouped: dict) -> dict | None:
    if project_key not in grouped:
        return None
    project = grouped[project_key]
    overrides = load_manual_overrides().get(project_key, {})
    merged_sections: dict[str, dict] = {}
    section_order: list[str] = []

    for sec in project.get("gpt_sections", []):
        title = sec.get("title", "기타").strip()
        if not title:
            continue
        if title not in merged_sections:
            merged_sections[title] = {"items": [], "notes": []}
            section_order.append(title)
        merged_sections[title]["items"].extend(sec.get("items", []) or [])
        merged_sections[title]["notes"].extend(sec.get("notes", []) or [])

    # manual overrides add-ons
    for title, items in (overrides.get("extra_items", {}) or {}).items():
        if title not in merged_sections:
            merged_sections[title] = {"items": [], "notes": []}
            section_order.append(title)
        merged_sections[title]["items"].extend(items)
    for title, notes in (overrides.get("extra_notes", {}) or {}).items():
        if title not in merged_sections:
            merged_sections[title] = {"items": [], "notes": []}
            section_order.append(title)
        merged_sections[title]["notes"].extend(notes)

    sections = []
    for title in section_order:
        block = merged_sections[title]
        items = list(dict.fromkeys(block["items"]))
        notes = list(dict.fromkeys(block["notes"]))
        custom_imgs = _load_custom_images_for_section(project_key, title)
        image_urls = [
            {"url": img["url"], "caption": img.get("caption", "")}
            for img in custom_imgs
        ]
        manual_imgs = (overrides.get("section_images") or {}).get(title)
        if manual_imgs is not None:
            image_urls = [{"url": u, "caption": ""} for u in manual_imgs]
        sections.append({
            "title": title,
            "items": items,
            "notes": notes,
            "image_urls": image_urls,
        })

    header_metrics = overrides.get("header_metrics", {})
    return {
        "key": project_key,
        "label": project["label"],
        "status": project["status"],
        "report_date": project.get("report_date"),
        "doc_id": project.get("doc_id"),
        "header_summary": project.get("header_summary", ""),
        "header_metrics": header_metrics,
        "sections": sections,
    }