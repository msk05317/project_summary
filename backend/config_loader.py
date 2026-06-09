# /Users/minseo/Desktop/project_summary/backend/config_loader.py
"""
사업부/프로젝트/매핑/UI 설정 단일 진입점.

원칙:
- 4개 JSON 파일은 이 모듈을 통해서만 읽는다.
- 외부 코드(main.py 등)는 절대 JSON을 직접 파싱하지 않는다.
- 운영 변경은 JSON만 수정하면 끝나도록 한다.
"""

from __future__ import annotations

import json
import threading
from pathlib import Path
from typing import Any, Iterable

BASE_DIR = Path(__file__).resolve().parent
CONFIG_DIR = BASE_DIR / "config"

DIVISIONS_FILE = CONFIG_DIR / "divisions.json"
PROJECTS_FILE = CONFIG_DIR / "projects.json"
RULES_FILE = CONFIG_DIR / "mapping_rules.json"
UI_FILE = CONFIG_DIR / "ui_settings.json"
MODELS_FILE = CONFIG_DIR / "models.json"

_lock = threading.Lock()
_cache: dict[str, Any] = {
    "divisions": None,
    "projects": None,
    "rules": None,
    "ui": None,
    "models": None,
    "loaded": False,
}


# ----------------------------- 내부 유틸 -----------------------------

def _read_json(path: Path) -> dict:
    if not path.exists():
        raise FileNotFoundError(f"설정 파일 없음: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def _normalize(text: str) -> str:
    if not text:
        return ""
    return "".join(text.split()).lower()


def _contains_any(haystack: str, needles: Iterable[str]) -> bool:
    h = _normalize(haystack)
    for n in needles:
        if n and _normalize(n) in h:
            return True
    return False


# ----------------------------- 로딩 -----------------------------

def load(force: bool = False) -> None:
    """4개 JSON을 메모리에 로드. force=True면 캐시 무시하고 재로드."""
    with _lock:
        if _cache["loaded"] and not force:
            return
        _cache["divisions"] = _read_json(DIVISIONS_FILE)
        _cache["projects"] = _read_json(PROJECTS_FILE)
        _cache["rules"] = _read_json(RULES_FILE)
        _cache["ui"] = _read_json(UI_FILE)
        _cache["models"] = _read_json(MODELS_FILE) if MODELS_FILE.exists() else {"models": []}
        _cache["loaded"] = True


def reload() -> None:
    """운영 중 JSON 수정 후 반영하고 싶을 때 사용."""
    load(force=True)


# ----------------------------- 조회 헬퍼 -----------------------------

def get_divisions(visible_only: bool = True) -> list[dict]:
    load()
    items = _cache["divisions"].get("divisions", [])
    if visible_only:
        items = [d for d in items if d.get("visible", True)]
    return sorted(items, key=lambda d: d.get("order", 9999))


def get_division(division_id: str) -> dict | None:
    load()
    for d in _cache["divisions"].get("divisions", []):
        if d.get("id") == division_id:
            return d
    return None


def get_projects(division_id: str | None = None, visible_only: bool = True) -> list[dict]:
    load()
    items = _cache["projects"].get("projects", [])
    if division_id:
        items = [p for p in items if p.get("division_id") == division_id]
    if visible_only:
        items = [p for p in items if p.get("visible", True)]
    return sorted(items, key=lambda p: p.get("order", 9999))


def get_project(project_id: str) -> dict | None:
    load()
    for p in _cache["projects"].get("projects", []):
        if p.get("id") == project_id:
            return p
    return None


def get_ui_settings() -> dict:
    load()
    return _cache["ui"]


# ----------------------------- 규칙 적용 -----------------------------

def _apply_merge_rules(project_id: str | None, text: str) -> str | None:
    """merge 규칙: 특정 키워드가 보이면 강제로 다른 project로 귀속."""
    load()
    for rule in _cache["rules"].get("rules", []):
        if rule.get("type") != "merge":
            continue
        if _contains_any(text, rule.get("from_keywords", [])):
            return rule.get("to_project_id") or project_id
    return project_id


def _violates_split_rule(project_id: str, text: str) -> bool:
    """split 규칙: 특정 project로 분류되려면 반드시 만족해야 하는 조건."""
    load()
    for rule in _cache["rules"].get("rules", []):
        if rule.get("type") != "split":
            continue
        if rule.get("protect_project_id") != project_id:
            continue
        must_any = rule.get("must_contain_any") or []
        must_not = rule.get("must_not_contain_any") or []
        if must_any and not _contains_any(text, must_any):
            return True
        if must_not and _contains_any(text, must_not):
            return True
    return False


def _alias_hit_project(text: str) -> str | None:
    """alias 규칙: 별칭으로 직접 매칭."""
    load()
    for rule in _cache["rules"].get("rules", []):
        if rule.get("type") != "alias":
            continue
        if _contains_any(text, rule.get("aliases", [])):
            return rule.get("project_id")
    return None

def _model_hit_project(text: str) -> str | None:
    """models.json 사전을 이용한 직접 매칭. 가장 신뢰도 높음."""
    load()
    models = _cache["models"].get("models", []) if _cache["models"] else []
    items = sorted(
        models,
        key=lambda m: max(
            [len(_normalize(m.get("name", "")))] +
            [len(_normalize(a)) for a in (m.get("aliases") or [])]
        ),
        reverse=True,
    )
    for m in items:
        terms = [m.get("name", "")] + list(m.get("aliases") or [])
        if _contains_any(text, terms):
            return m.get("project_id")
    return None
# ----------------------------- 분류기 -----------------------------

def classify_project(text: str, hint_division_id: str | None = None) -> str | None:
    """
    카드 텍스트(제목 + 헤드라인 등)를 받아 project_id를 추정한다.
    1) alias 규칙 우선
    2) 프로젝트 keywords / aliases / label 매칭
    3) merge 규칙으로 후보 보정
    4) split 규칙 위반 시 그 후보는 거절
    """
    if not text:
        return None
    load()

    # 0) 모델 사전 직격 (가장 신뢰도 높음)
    model_hit = _model_hit_project(text)
    
    # 1) alias 직격
    alias_hit = _alias_hit_project(text)

    # 2) 후보 점수화
    candidates: list[tuple[float, str]] = []
    for p in _cache["projects"].get("projects", []):
        if hint_division_id and p.get("division_id") != hint_division_id:
            continue
        terms = []
        terms.append(p.get("label", ""))
        terms.extend(p.get("aliases", []) or [])
        terms.extend(p.get("keywords", []) or [])
        score = 0.0
        for t in terms:
            if not t:
                continue
            if _normalize(t) and _normalize(t) in _normalize(text):
                # 긴 키워드가 더 신뢰도 높음
                score = max(score, min(1.0, len(_normalize(t)) / 6.0))
        if score > 0:
            candidates.append((score, p["id"]))

    candidates.sort(reverse=True)

    project_id: str | None = (
        model_hit
        or alias_hit
        or (candidates[0][1] if candidates else None)
    )

    # 3) merge 규칙 적용
    project_id = _apply_merge_rules(project_id, text)

    # 4) split 규칙 위반 시 후보 폐기
    if project_id and project_id != model_hit and _violates_split_rule(project_id, text):
        # 차선 후보 탐색
        for _, cid in candidates:
            if cid != project_id and not _violates_split_rule(cid, text):
                project_id = cid
                break
        else:
            project_id = None

    return project_id


def classify_division(text: str) -> str | None:
    """텍스트에서 사업부를 직접 추정. 보통은 project_id로부터 derive 하는 게 더 정확."""
    pid = classify_project(text)
    if pid:
        p = get_project(pid)
        if p:
            return p.get("division_id")
    return None


def derive_division_from_project(project_id: str | None) -> str | None:
    if not project_id:
        return None
    p = get_project(project_id)
    return p.get("division_id") if p else None


# ----------------------------- 뱃지 라벨 -----------------------------

def badge_label_for_project(project_id: str | None) -> str | None:
    p = get_project(project_id) if project_id else None
    if not p:
        return None
    return p.get("badge_label") or p.get("label")


def badge_label_for_division(division_id: str | None) -> str | None:
    d = get_division(division_id) if division_id else None
    if not d:
        return None
    return d.get("badge_short_label") or d.get("label")
