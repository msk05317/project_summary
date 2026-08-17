from typing import Optional
"""
프로젝트(부서) 단위 보기 모듈
- GPT가 자동 정리한 sections를 그대로 사용
- 프로젝트 리스트는 고정, 키워드로 자동 매핑
- 섹션 이미지 매칭은 '부분 매칭' 방식 (admin 업로드 섹션명이 GPT 섹션명과 달라도 매칭됨)
"""
import json
import re
from pathlib import Path

import re as _re_section_title

def _normalize_section_title(title) -> str:
    """
    N2 정규화: 앞부분의 번호 prefix만 제거.
    예) "2-1. 내재화 프레임 진행현황(화성 17종)" -> "내재화 프레임 진행현황(화성 17종)"
        "5. 직납프레임 TREOS"                  -> "직납프레임 TREOS"
    """
    if not isinstance(title, str):
        return ""
    t = title.strip()
    t = _re_section_title.sub(r"^\s*\d+(?:[-.]\d+)*[.)\]]?\s+", "", t)
    t = _re_section_title.sub(r"\s+", " ", t)
    return t.strip()


def _canonical_section_match_key(title, existing_keys):
    """
    하이브리드 매칭(C):
    - 기본 키는 _normalize_section_title 결과 (lowercase)
    - 단, 그 키가 기존에 채택된 어떤 키와 'prefix 포함 관계' 이면 그 키로 합침
      예) 기존 '내재화 프레임 진행현황(화성 17종)' 가 채택돼 있으면
          새로 들어온 '내재화 프레임 진행현황' 은 같은 카드로 봄
    - prefix 비교는 양방향: 더 긴 쪽이 더 짧은 쪽을 prefix 로 가지면 같은 카드
    - 단, prefix 뒤가 (한글/영문/숫자) 글자로 바로 이어지면 안 됨 → 공백/괄호/구분자만 허용
    """
    base = _normalize_section_title(title).lower()
    if not base:
        return base
    for k in existing_keys:
        if not k:
            continue
        a, b = (base, k) if len(base) >= len(k) else (k, base)
        if a == b:
            return k
        if a.startswith(b):
            rest = a[len(b):]
            # 다음 글자가 단어 경계여야 함 (괄호/공백/구분자)
            if rest[:1] in (" ", "(", "[", "{", "-", "_", ".", ",", ":", "/"):
                return k
    return base



BASE_DIR = Path(__file__).parent
import os
DATA_DIR = Path(os.getenv("DATA_DIR", str(BASE_DIR)))

MANUAL_OVERRIDES_FILE = DATA_DIR / "manual_overrides.json"
CUSTOM_IMAGES_MAPPING_FILE = DATA_DIR / "image_mappings.json"

# 1. 프로젝트 라벨 (8개 고정)
PROJECT_LABELS = {
    "chamber": "챔버",
    "havaplate": "하바플레이트",
    "hrva_plate": "하바플레이트",
    "hrva_plate": "하바플레이트",
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
    (["하바플레이트", "하바 플레이트", "하바", "havaplate", "hava plate", "hrva_plate", "hrva plate", "hrvaplate"], "hrva_plate"),
    (["cup", "컵"], "cup"),
    (["파워박스", "powerbox", "power box", "aether gdx", "aether", "에테르",
      "mach i", "mach 1", "machi"], "powerbox"),
    (["메이저모듈", "메이저 모듈", "major module", "메이져모듈", "메이져 모듈",
      "efem", "vtm", "텍슨", "긴급 신규"], "major_module"),
    (["프레임", "frame", "내재화프레임", "내재화 프레임",
      "cefem", "treos", "quaros", "faraday", "직납프레임", "직납"], "frame"),
]


# 한국어 초성/중성/종성 리스트
_CHOSUNG = ['ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ']
_JUNGSUNG = ['ㅏ', 'ㅐ', 'ㅑ', 'ㅒ', 'ㅓ', 'ㅔ', 'ㅕ', 'ㅖ', 'ㅗ', 'ㅘ', 'ㅙ', 'ㅚ', 'ㅛ', 'ㅜ', 'ㅝ', 'ㅞ', 'ㅟ', 'ㅠ', 'ㅡ', 'ㅢ', 'ㅣ']
_JONGSUNG = ['', 'ㄱ', 'ㄲ', 'ㄳ', 'ㄴ', 'ㄵ', 'ㄶ', 'ㄷ', 'ㄹ', 'ㄺ', 'ㄻ', 'ㄼ', 'ㄽ', 'ㄾ', 'ㄿ', 'ㅀ', 'ㅁ', 'ㅂ', 'ㅄ', 'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ']

def _decompose_hangul(char: str) -> tuple:
    """한글 문자를 초성/중성/종성으로 분리"""
    if '가' <= char <= '힣':
        code = ord(char) - 0xAC00
        jong = code % 28
        jung = (code // 28) % 21
        cho = (code // 28) // 21
        return (_CHOSUNG[cho], _JUNGSUNG[jung], _JONGSUNG[jong])
    return (char, '', '')

def _get_phonetic_key(text: str) -> str:
    """텍스트의 발음 키 생성 (초성+중성만, 종성 생략)"""
    result = []
    for char in text:
        if '가' <= char <= '힣':
            cho, jung, _ = _decompose_hangul(char)
            result.append(cho + jung)
        else:
            result.append(char.lower())
    return ''.join(result)

def _phonetic_similarity(a: str, b: str) -> float:
    """두 한국어 텍스트의 발음 유사도 (0.0 ~ 1.0)"""
    if not a or not b:
        return 0.0
    
    key_a = _get_phonetic_key(a)
    key_b = _get_phonetic_key(b)
    
    # 완전 일치
    if key_a == key_b:
        return 1.0
    
    # 부분 일치 (한쪽이 다른 쪽에 포함)
    if key_a in key_b or key_b in key_a:
        shorter = min(len(key_a), len(key_b))
        longer = max(len(key_a), len(key_b))
        return shorter / longer
    
    # 레벤슈타인 거리 기반 유사도
    distance = _levenshtein(key_a, key_b)
    max_len = max(len(key_a), len(key_b))
    if max_len == 0:
        return 0.0
    return 1.0 - (distance / max_len)

def _levenshtein(a: str, b: str) -> int:
    """레벤슈타인 거리 계산"""
    if len(a) < len(b):
        return _levenshtein(b, a)
    if len(b) == 0:
        return len(a)
    
    previous_row = range(len(b) + 1)
    for i, c1 in enumerate(a):
        current_row = [i + 1]
        for j, c2 in enumerate(b):
            insertions = previous_row[j + 1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row.append(min(insertions, deletions, substitutions))
        previous_row = current_row
    
    return previous_row[-1]

def _get_project_aliases(project_key: str) -> list[str]:
    """프로젝트의 모든 별칭/발음 변형 반환"""
    aliases = []
    
    # 기본 키워드
    for keywords, key in PRODUCT_TO_PROJECT:
        if key == project_key:
            aliases.extend(keywords)
    
    # 발음 변형 추가 (하바플레이트 예시)
    if project_key == "hrva_plate":
        aliases.extend([
            "하바", "하바플레이트", "하바 플레이트", "하바플레이트",
            "하버", "하버플레이트", "하버 플레이트",
            "하봐", "하봐플레이트",
            "허버", "허버플레이트",
            "hrva", "hava", "harva", "herva"
        ])
    elif project_key == "chamber":
        aliases.extend(["챔버", "챔버", "chamber", "쳄버", "챔벌"])
    elif project_key == "powerbox":
        aliases.extend(["파워박스", "파워 박스", "파워빅스", "파워빅스", "powerbox", "power box"])
    elif project_key == "major_module":
        aliases.extend(["메이저모듈", "메이저 모듈", "메이저모듈", "major module", "majormodule"])
    elif project_key == "enclosure":
        aliases.extend([
            "엔클로저", "엔클로저", "엔클로져",
            "엔크루저", "엔크루져", "엔크로저", "엔크로져",
            "앤크로저", "앤크루저", "앤클로저", "앤클로져",
            "인클로저", "인크루저",
            "enclosure", "encloser"
        ])
    elif project_key == "frame":
        aliases.extend(["프레임", "프래임", "프레임", "frame"])
    
    return list(set(aliases))

def _match_project_key(product_name: str) -> Optional[str]:
    """프로젝트 키 매칭 (발음 유사도 기반 퍼지 매칭)"""
    if not product_name:
        return None
    
    name = product_name.strip()
    best_match = None
    best_score = 0.0
    
    # 1. 정확한 키워드 매칭 (기존 로직)
    name_lower = name.lower()
    for keywords, key in PRODUCT_TO_PROJECT:
        for kw in keywords:
            if kw.lower() in name_lower:
                return key
    
    # 2. 발음 유사도 매칭 (퍼지)
    for keywords, key in PRODUCT_TO_PROJECT:
        all_aliases = _get_project_aliases(key)
        for alias in all_aliases:
            score = _phonetic_similarity(name, alias)
            if score > best_score and score >= 0.6:  # 60% 이상 유사하면 매칭
                best_score = score
                best_match = key
    
    return best_match


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
            # status가 빈 문자열이면 sections를 보고 계산
            if not status or status == "":
                # main.py의 _calc_card_status와 동일 로직 (순환 import 방지)
                priority = {"RED": 5, "ORANGE": 4, "BLUE": 3, "GREEN": 2, "BLACK": 1}
                best = "BLACK"
                has_sales = False
                for sec in (product.get("sections") or []):
                    if (sec.get("sales_summary") or "").strip():
                        has_sales = True
                    for it in (sec.get("items") or []):
                        if not isinstance(it, dict):
                            continue
                        due = it.get("due_date") or ""
                        # due_date 기반 상태 판정 (간소화)
                        if due:
                            from datetime import datetime, date
                            try:
                                due_dt = datetime.fromisoformat(due.replace("Z", "+00:00")).date()
                                today = date.today()
                                if due_dt < today:
                                    s = "RED"
                                elif (due_dt - today).days <= 3:
                                    s = "ORANGE"
                                elif (due_dt - today).days <= 7:
                                    s = "BLUE"
                                else:
                                    s = "GREEN"
                            except Exception:
                                s = "BLACK"
                            if priority.get(s, 0) > priority.get(best, 0):
                                best = s
                                if best == "RED":
                                    break
                    if best == "RED":
                        break
                if best == "BLACK" and has_sales:
                    status = "GREEN"
                else:
                    status = best
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
    # 정규화된 title 키 → 이미 채택된 원본 title 매핑.
    # 최신 보고서가 먼저 들어오므로 처음 등장한 title 이 "이김" (R1: 최신 덮어쓰기).
    key_to_title: dict[str, str] = {}


    for sec in project.get("gpt_sections", []):
        title = sec.get("title", "기타").strip()
        if not title:
            continue
        key = _canonical_section_match_key(title, list(key_to_title.keys()))
        if key in key_to_title:
            # 이미 더 최신 보고서의 동일 카드가 채택됨 → 옛날 보고서는 무시 (overlap 방지)
            continue
        key_to_title[key] = title
        merged_sections[title] = {
            "items": list(sec.get("items", []) or []),
            "notes": list(sec.get("notes", []) or []),
        }
        section_order.append(title)

    # manual overrides add-ons (관리자 수동 보강은 누적으로 더해줌)
    for title, items in (overrides.get("extra_items", {}) or {}).items():
        key = _canonical_section_match_key(title, list(key_to_title.keys()))
        target_title = key_to_title.get(key)
        if target_title is None:
            merged_sections[title] = {"items": list(items), "notes": []}
            section_order.append(title)
            key_to_title[key] = title
        else:
            merged_sections[target_title]["items"].extend(items)

    for title, notes in (overrides.get("extra_notes", {}) or {}).items():
        key = _canonical_section_match_key(title, list(key_to_title.keys()))
        target_title = key_to_title.get(key)
        if target_title is None:
            merged_sections[title] = {"items": [], "notes": list(notes)}
            section_order.append(title)
            key_to_title[key] = title
        else:
            merged_sections[target_title]["notes"].extend(notes)

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