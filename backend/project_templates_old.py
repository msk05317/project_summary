"""
프로젝트(부서) 단위 보기를 위한 템플릿/매핑 모듈
- 제품명 → 프로젝트 키 매핑
- 프로젝트별 섹션 템플릿 정의
- aggregate_projects: 신호등 데이터 → 프로젝트별로 그룹화
- build_project_detail: 프로젝트 상세 응답 생성
"""
import json
from pathlib import Path

MANUAL_OVERRIDES_FILE = Path(__file__).parent / "manual_overrides.json"


# =========================================================
# 1. 프로젝트 라벨 (버튼에 표시될 한글 이름)
# =========================================================
PROJECT_LABELS = {
    # 파워박스 계열
    "powerbox": "파워박스",

    # 메이저 모듈
    "chamber": "챔버",
    "enclosure": "엔클로저",
    "havaplate": "하바플레이트",
    "plating_cell": "플레이팅 셀",
    "cup": "CUP",
    "xylan": "자일란 코팅",
    "torlon": "톨론",

    # 반도체 장비
    "efem": "EFEM",
    "vtm": "VTM",
    "cefem": "CEFEM",
    "sabre": "SABRE",
    "quaros": "QUAROS",
    "eos_chamber": "EOS 챔버",

    # 내재화
    "spacex": "Space X",
    "kla": "KLA",
    "cleaning": "세정",
    "ram_casting": "램 캐스팅",
}


# =========================================================
# 2. 제품/키워드 → 프로젝트 키 매핑
#    (GPT가 뽑은 product 이름을 보고 어느 프로젝트인지 자동 판정)
# =========================================================
PRODUCT_TO_PROJECT = [
    # (검색 키워드 리스트, 프로젝트 키)
    (["aether gdx", "aether", "에테르", "파워박스", "powerbox"], "powerbox"),
    (["챔버", "chamber"], "chamber"),
    (["엔클로저", "enclosure"], "enclosure"),
    (["하바플레이트", "하바", "havaplate"], "havaplate"),
    (["플레이팅", "plating"], "plating_cell"),
    (["cup", "컵"], "cup"),
    (["자일란", "xylan"], "xylan"),
    (["톨론", "torlon"], "torlon"),
    (["efem"], "efem"),
    (["vtm"], "vtm"),
    (["cefem"], "cefem"),
    (["sabre", "세이버"], "sabre"),
    (["quaros", "쿠아로스"], "quaros"),
    (["eos"], "eos_chamber"),
    (["space x", "spacex", "스페이스x"], "spacex"),
    (["kla"], "kla"),
    (["세정", "cleaning"], "cleaning"),
    (["램 캐스팅", "ram casting", "캐스팅"], "ram_casting"),
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


# =========================================================
# 3. 프로젝트별 섹션 템플릿
#    - 같은 구조면 __default__ 사용
# =========================================================
PROJECT_TEMPLATES = {
    "__default__": {
        "header_metrics": {},
        "sections": [
            {"title": "양산"},
            {"title": "개발"},
            {"title": "EMA"},
            {"title": "주차별 출하실적 및 계획"},
        ],
    },
    "powerbox": {
        "header_metrics": {
            "sales_target_2026": "$2,668만",
        },
        "sections": [
            {"title": "양산"},
            {"title": "개발"},
            {"title": "EMA"},
            {"title": "주차별 출하실적 및 계획"},
        ],
    },
    "chamber": {
        "header_metrics": {},
        "sections": [
            {"title": "양산"},
            {"title": "개발"},
            {"title": "EMA"},
            {"title": "주차별 출하실적 및 계획"},
        ],
    },
    "efem": {
        "header_metrics": {},
        "sections": [
            {"title": "양산"},
            {"title": "개발"},
            {"title": "EMA"},
            {"title": "주차별 출하실적 및 계획"},
        ],
    },
    "vtm": {
        "header_metrics": {},
        "sections": [
            {"title": "양산"},
            {"title": "개발"},
            {"title": "EMA"},
            {"title": "주차별 출하실적 및 계획"},
        ],
    },
}


# =========================================================
# 4. manual_overrides.json 로더
# =========================================================
def load_manual_overrides() -> dict:
    if MANUAL_OVERRIDES_FILE.exists():
        try:
            return json.loads(MANUAL_OVERRIDES_FILE.read_text(encoding="utf-8"))
        except Exception:
            return {}
    return {}


# =========================================================
# 5. 신호등 우선순위
# =========================================================
def _status_priority(status: str) -> int:
    return {"RED": 3, "BLUE": 2, "BLACK": 1}.get(status, 0)


def _worst_status(a: str, b: str) -> str:
    return a if _status_priority(a) >= _status_priority(b) else b


# =========================================================
# 6. 보고서 데이터 → 프로젝트별로 그룹화
# =========================================================
def aggregate_projects(reports_latest: list) -> dict:
    """
    reports_latest.json 의 모든 보고서를 읽어서
    프로젝트 키 단위로 묶어준다.
    """
    grouped: dict = {}

    for report in reports_latest:
        # 기존 데이터 구조 호환:
        # - report_meta.date 우선, 없으면 report_date
        report_date = (
            report.get("report_meta", {}).get("date")
            or report.get("report_date")
        )
        # slide_images: {"1": "/slides/.../slide_01.png", ...} 형태
        slide_images = report.get("slide_images", {})
        # section_images (새 버전): {"양산": [...], ...}
        section_images = report.get("section_images", {})

        for product in report.get("products", []):
            # product 이름: 새 버전은 "product", 기존은 "name"
            product_name = product.get("product") or product.get("name", "")
            key = _match_project_key(product_name)
            if not key:
                continue

            label = PROJECT_LABELS.get(key, product_name)
            status = product.get("status", "BLACK")

            if key not in grouped:
                grouped[key] = {
                    "label": label,
                    "status": status,
                    "report_date": report_date,
                    "reports": [],
                    "section_items": {},
                    "section_notes": {},
                    "slide_images_map": {},  # {슬라이드번호: url}
                    "product_source_slides": {},  # {제품명: [슬라이드번호]}
                }
            else:
                grouped[key]["status"] = _worst_status(
                    grouped[key]["status"], status
                )

            grouped[key]["reports"].append({
                **report,
                "_matched_product": product_name,
            })

            # 기존 데이터: headline, critical_issues, next_actions, kpis 등을
            # section_items 형태로 자동 변환
            headline = product.get("headline", "")
            if headline:
                # status 에 따라 적절한 섹션에 배치
                grouped[key]["section_items"].setdefault("양산", []).append(
                    f"{product_name}: {headline}"
                )

            # KPI 정보
            for kpi in product.get("kpis", []) or []:
                label_k = kpi.get("label", "")
                value = kpi.get("value", "")
                target = kpi.get("target", "")
                if label_k and value:
                    txt = f"{label_k}: {value}"
                    if target:
                        txt += f" / 목표 {target}"
                    grouped[key]["section_items"].setdefault(
                        "주차별 출하실적 및 계획", []
                    ).append(txt)

            # 이슈 → 노트
            for issue in product.get("critical_issues", []) or []:
                title = issue.get("title", "")
                detail = issue.get("detail", "")
                if title or detail:
                    grouped[key]["section_notes"].setdefault(
                        "주차별 출하실적 및 계획", []
                    ).append(f"{title} - {detail}".strip(" -"))

            # 마일스톤 → 개발 섹션
            for ms in product.get("milestones", []) or []:
                date = ms.get("date", "")
                event = ms.get("event", "")
                if event:
                    grouped[key]["section_items"].setdefault(
                        "개발", []
                    ).append(f"{date}: {event}" if date else event)

            # next_actions → EMA 또는 개발 섹션
            for act in product.get("next_actions", []) or []:
                grouped[key]["section_items"].setdefault(
                    "EMA", []
                ).append(act)

            # 신규 버전 section_items 도 병합
            for sec, items in (product.get("section_items") or {}).items():
                grouped[key]["section_items"].setdefault(sec, []).extend(items)
            for sec, notes in (product.get("section_notes") or {}).items():
                grouped[key]["section_notes"].setdefault(sec, []).extend(notes)

            # 슬라이드 이미지 매핑 저장 (제품별 source_slide_numbers 사용)
            for num_str, url in slide_images.items():
                grouped[key]["slide_images_map"][str(num_str)] = url

            source_slides = product.get("source_slide_numbers", []) or []
            if source_slides:
                grouped[key]["product_source_slides"].setdefault(
                    product_name, []
                ).extend(source_slides)

            # section_images (새 버전 차트 자동 추출) 도 저장
            grouped[key].setdefault("_section_images_raw", {})
            for sec_name, urls in section_images.items():
                grouped[key]["_section_images_raw"].setdefault(sec_name, []).extend(urls)

    # 라벨 정리
    for key, val in grouped.items():
        val["label"] = PROJECT_LABELS.get(key, val["label"])

    return grouped



# =========================================================
# 7. 프로젝트 상세 응답 생성
# =========================================================
def build_project_detail(project_key: str, grouped: dict) -> dict | None:
    """
    프로젝트 상세 응답 생성
    - 텍스트는 GPT 요약 결과 사용
    - 이미지는 키워드 기반 자동 crop 결과 사용
    - manual_overrides.json 으로 수동 보정 가능
    """
    if project_key not in grouped:
        return None

    project = grouped[project_key]
    template = PROJECT_TEMPLATES.get(project_key, PROJECT_TEMPLATES["__default__"])
    overrides = load_manual_overrides().get(project_key, {})

    # 자동 추출된 섹션별 차트 (이번 프로젝트에 매칭된 report 들에서만)
    auto_section_images: dict[str, list[str]] = {}
    for report in project.get("reports", []):
        for sec_name, urls in (report.get("section_images") or {}).items():
            auto_section_images.setdefault(sec_name, []).extend(urls)

    # 헤더 (수동 매출목표 등)
    header_metrics = {
        **template.get("header_metrics", {}),
        **(overrides.get("header_metrics", {})),
    }

    # 섹션 구성
    sections = []
    for sec_def in template["sections"]:
        title = sec_def["title"]

        # 1) 텍스트 항목
        items = list(project.get("section_items", {}).get(title, []))
        items += list(overrides.get("extra_items", {}).get(title, []))

        # 2) 노트
        notes = list(project.get("section_notes", {}).get(title, []))
        notes += list(overrides.get("extra_notes", {}).get(title, []))

        # 3) 이미지 - 자동 매칭된 차트
        images = list(
            project.get("_section_images_raw", {}).get(title, [])
        )

        # (b) 자동 추출이 없으면 → 제품의 source_slide_numbers 기반으로
        #     slide_images 에서 가져오기 (기존 데이터 호환)
        if not images:
            slide_map = project.get("slide_images_map", {})
            source_slides_all = []
            for product_slides in project.get("product_source_slides", {}).values():
                source_slides_all.extend(product_slides)

            # 섹션과 슬라이드 매칭은 단순화: 모든 source slide 를 1개씩만 보여줌
            # 중복 제거
            seen = set()
            for num in source_slides_all:
                key_num = str(num)
                if key_num in seen:
                    continue
                seen.add(key_num)
                url = slide_map.get(key_num)
                if url:
                    images.append(url)
                if len(images) >= 1:  # 섹션당 1장만
                    break

        # (c) manual override
        manual_imgs = overrides.get("section_images", {}).get(title)
        if manual_imgs is not None:
            images = list(manual_imgs)