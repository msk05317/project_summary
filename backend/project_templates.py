"""
프로젝트(부서) 단위 보기 모듈
- GPT가 자동 정리한 sections를 그대로 사용
- 8개 고정 프로젝트, 키워드로 자동 매핑
- summary_bullets(핵심 3줄) 지원
- 사용자 업로드 이미지 결합
"""
import json
from pathlib import Path

MANUAL_OVERRIDES_FILE = Path(__file__).parent / "manual_overrides.json"
CUSTOM_IMAGES_MAPPING_FILE = Path(__file__).parent / "image_mappings.json"

# ============================================================
# 1. 프로젝트 라벨 (8개 고정)
# ============================================================
PROJECT_LABELS = {
    "chamber":           "챔버",
    "havaplate":         "하바플레이트",
    "enclosure":         "엔클로저",
    "casting_enclosure": "캐스팅 엔클로저",
    "cup":               "CUP",
    "powerbox":          "파워박스",
    "major_module":      "메이저모듈",
    "frame":             "프레임",
}

# ============================================================
# 2. 키워드 → 프로젝트 매핑
#    리스트 순서대로 매칭 (구체적인 것 먼저!)
# ============================================================
PRODUCT_TO_PROJECT = [
    # --- 캐스팅 엔클로저 (엔클로저보다 먼저) ---
    (["캐스팅 엔클로저", "캐스팅엔클로저", "casting enclosure", "캐스팅"], "casting_enclosure"),

    # --- 엔클로저 ---
    (["엔클로저", "enclosure"], "enclosure"),

    # --- 챔버 ---
    (["챔버", "chamber", "메탈챔버", "메탈 챔버", "dep 챔버", "dep챔버", "탑플레이트"], "chamber"),

    # --- 하바플레이트 ---
    (["하바플레이트", "하바 플레이트", "하바", "havaplate", "hava plate"], "havaplate"),

    # --- CUP ---
    (["cup", "컵"], "cup"),

    # --- 파워박스 ---
    (["파워박스", "powerbox", "power box", "aether gdx", "aether", "에테르",
      "양산 13종", "양산 14종", "ema 33종", "ema 31종", "kiyo"], "powerbox"),

    # --- 프레임 (메이저모듈보다 먼저, 더 구체적) ---
    (["프레임", "frame", "내재화프레임", "내재화 프레임",
      "cefem 프레임", "cefem프레임",
      "직납프레임", "직납 프레임",
      "treos", "quaros", "faraday",
      "mach i", "machi", "mach1", "mach 1",
      "sense", "sfem"], "frame"),

    # --- 메이저모듈 (EFEM/VTM 등 모듈 단위) ---
    (["메이저모듈", "메이저 모듈", "major module", "메이져모듈", "메이져 모듈",
      "efem", "vtm", "cefem",
      "텍슨화성", "텍슨 화성"], "major_module"),
]

def _match_project_key(text: str) -> str | None:
    if not text:
        return None
    name = text.lower()
    for keywords, key in PRODUCT_TO_PROJECT:
        for kw in keywords:
            if kw.lower() in name:
                return key
    return None

# ============================================================
# 3. 외부 파일 로더
# ============================================================
def load_manual_overrides() -> dict:
    if MANUAL_OVERRIDES_FILE.exists():
        try:
            return json.loads(MANUAL_OVERRIDES_FILE.read_text(encoding="utf-8"))
        except Exception:
            return {}
    return {}

def _load_custom_images_for_section(project_key: str, section_title: str) -> list[dict]:
    """admin 페이지에서 업로드한 이미지 중 해당 (project, section) 매핑 반환"""
    if not CUSTOM_IMAGES_MAPPING_FILE.exists():
        return []
    try:
        data = json.loads(CUSTOM_IMAGES_MAPPING_FILE.read_text(encoding="utf-8"))
    except Exception:
        return []
    return [
        img for img in data.get("images", [])
        if img.get("project_key") == project_key and img.get("section_title") == section_title
    ]

# ============================================================
# 4. 신호등 우선순위
# ============================================================
def _status_priority(status: str) -> int:
    return {"RED": 3, "BLUE": 2, "BLACK": 1}.get(status, 0)

def _worst_status(a: str, b: str) -> str:
    return a if _status_priority(a) >= _status_priority(b) else b

# ============================================================
# 5. 보고서 → 프로젝트별 그룹화
# ============================================================
def aggregate_projects(reports_latest: list[dict]) -> dict:
    grouped: dict[str, dict] = {}

    for report in reports_latest:
        report_date = report.get("report_meta", {}).get("date") or report.get("report_date")
        doc_id = report.get("doc_id", "")
        report_family = (report.get("report_meta", {}).get("report_family")
                         or report.get("report_family", ""))

        for product in report.get("products", []):
            product_name = product.get("name") or product.get("product", "")
            category = product.get("category", "")

            # 1차: 제품명, 2차: 카테고리, 3차: report_family 로 매칭
            key = (_match_project_key(product_name)
                   or _match_project_key(category)
                   or _match_project_key(report_family))
            if not key:
                # 디버깅: 매핑 실패한 항목 로그
                print(f"⚠️  매핑 실패: name={product_name!r}, category={category!r}, family={report_family!r}")
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
                    "summary_bullets": list(product.get("summary_bullets") or []),
                    "gpt_sections": [],
                    "matched_products": [],
                }
            else:
                grouped[key]["status"] = _worst_status(grouped[key]["status"], status)
                if product.get("header_summary"):
                    grouped[key]["header_summary"] = product["header_summary"]
                # summary_bullets는 누적 (단, 최대 5개로 제한)
                for b in (product.get("summary_bullets") or []):
                    if b not in grouped[key]["summary_bullets"]:
                        grouped[key]["summary_bullets"].append(b)
                grouped[key]["summary_bullets"] = grouped[key]["summary_bullets"][:5]

            grouped[key]["matched_products"].append(product_name)

            # GPT가 만든 sections 누적
            for sec in (product.get("sections") or []):
                grouped[key]["gpt_sections"].append(sec)

    return grouped

# ============================================================
# 6. 프로젝트 상세 응답 생성
# ============================================================
def build_project_detail(project_key: str, grouped: dict) -> dict | None:
    if project_key not in grouped:
        return None

    project = grouped[project_key]
    overrides = load_manual_overrides().get(project_key, {})

    # sections를 title 기준으로 병합
    merged_sections: dict[str, dict] = {}
    section_order: list[str] = []

    for sec in project.get("gpt_sections", []):
        title = (sec.get("title") or "기타").strip()
        if not title:
            continue
        if title not in merged_sections:
            merged_sections[title] = {"items": [], "notes": []}
            section_order.append(title)
        merged_sections[title]["items"].extend(sec.get("items", []) or [])
        merged_sections[title]["notes"].extend(sec.get("notes", []) or [])

    # manual_overrides의 추가 items/notes
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

    # 최종 sections 빌드 (이미지 첨부)
    sections = []
    for title in section_order:
        block = merged_sections[title]
        # 중복 제거 (순서 유지)
        items = list(dict.fromkeys(block["items"]))
        notes = list(dict.fromkeys(block["notes"]))

        # 사용자 업로드 이미지
        custom_imgs = _load_custom_images_for_section(project_key, title)
        image_urls = [
            {"url": img["url"], "caption": img.get("caption", "")}
            for img in custom_imgs
        ]

        # manual_overrides 강제 지정 (있으면 덮어쓰기)
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
        "summary_bullets": project.get("summary_bullets", []),
        "header_metrics": header_metrics,
        "matched_products": project.get("matched_products", []),
        "sections": sections,
    }