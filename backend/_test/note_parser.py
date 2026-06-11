"""
주간 노트 텍스트 → 구조화 JSON 파서 (검증용)

규칙:
- <텍스트>           : 새 프로젝트 카드 시작
- 1. 2. 3. 또는 1)2) : 새 섹션 시작
- -, ▸ 시작          : 일반 불릿
- * 시작             : 빨간색 강조 불릿
- 들여쓰기 + - / →  : 서브 항목 (한 단계 들여쓰기)
"""
import re
import json
from typing import List, Dict, Any


def _line_indent(line: str) -> int:
    """선행 공백 수 반환"""
    return len(line) - len(line.lstrip(' '))


def _strip_bullet(text: str) -> str:
    """선행 기호 제거 + 정리"""
    text = text.strip()
    # 선행 기호 제거
    for prefix in ['- ', '▸ ', '• ', '* ', '→ ', '=> ', '-> ']:
        if text.startswith(prefix):
            text = text[len(prefix):].strip()
            break
    return text


def parse_note(text: str) -> List[Dict[str, Any]]:
    """텍스트를 프로젝트 카드 리스트로 변환"""
    lines = text.splitlines()
    cards: List[Dict[str, Any]] = []
    current_card: Dict[str, Any] | None = None
    current_section: Dict[str, Any] | None = None
    current_item: Dict[str, Any] | None = None  # 마지막 항목 (서브 아이템 추가용)

    # 정규식
    re_card_header = re.compile(r'^\s*<([^<>]+)>\s*$')
    re_section_header = re.compile(r'^\s*(\d+)[\.\)]\s+(.+)$')

    for raw in lines:
        if not raw.strip():
            continue

        indent = _line_indent(raw)
        line = raw.strip()

        # 1) <프로젝트 카드>
        m = re_card_header.match(raw)
        if m:
            title = m.group(1).strip()
            current_card = {"title": title, "sections": []}
            cards.append(current_card)
            current_section = None
            current_item = None
            continue

        # 2) 1. 섹션 / 1) 섹션
        m = re_section_header.match(raw)
        if m and current_card is not None:
            # 들여쓰기가 깊지 않을 때만 새 섹션
            if indent <= 4:
                section_title = m.group(2).strip()
                current_section = {"title": section_title, "items": []}
                current_card["sections"].append(current_section)
                current_item = None
                continue

        # 카드가 아직 없으면 "기본 카드" 자동 생성
        if current_card is None:
            current_card = {"title": "기타", "sections": []}
            cards.append(current_card)

        # 섹션이 아직 없으면 "기본 섹션" 자동 생성
        if current_section is None:
            current_section = {"title": "내용", "items": []}
            current_card["sections"].append(current_section)

        # 3) 항목 종류 결정
        # 빨간 강조: * 로 시작
        if line.startswith('*'):
            item_type = 'highlight'
        elif line.startswith('→') or line.startswith('=>') or line.startswith('->'):
            item_type = 'sub'
        elif line.startswith('-') or line.startswith('▸') or line.startswith('•'):
            item_type = 'bullet'
        else:
            # 기호 없이 들여쓰기만 있는 경우 → 이전 항목의 서브로 처리
            if current_item is not None and indent > 0:
                item_type = 'sub'
            else:
                item_type = 'bullet'

        cleaned = _strip_bullet(line)

        # 들여쓰기 깊은 항목은 서브로 강제
        if indent >= 6 and item_type == 'bullet':
            item_type = 'sub'

        item = {"type": item_type, "text": cleaned, "indent": min(indent // 2, 3)}

        # sub 타입은 이전 일반 항목의 children 으로 붙이기 시도
        if item_type == 'sub' and current_item is not None:
            current_item.setdefault('children', []).append(item)
        else:
            current_section["items"].append(item)
            current_item = item

    return cards


# === 검증 실행 ===
if __name__ == "__main__":
    sample = """<페러데이 4T>
1. LPM
 - 5호기, 6호기-테스트완료(4/3) -> 정상 문제없음(10,000회)
 - 7호기-테스트진행중(6/7)
2. EFEM(전시품)
 - 화성 조립완료/테스트중~6/9, 6/15 발송(선박) 6/29 텍슨도착 예상
 - 설치시 페러데이 출징 지원예정

<프레임>
 1. CEFEM 프레임
  *판매가 화성(212 : 3.9K, 110 : 3.0K), VN(212 : 2.4K / 110 : 2.5K)
  (CEFEM 프레임 출하계획)
  * 6월 화성(51대) 우선 출고후 VN출하 진행.
    - 화성 출고 대기중 (우드박스 미입고, 메이져모듈 창고 공간부족)

- 카말 방문 완료(5/11~12)
   * 5/20 SI리포트 최종 리뷰 완료 => 카말은 승인 / 오웬 최종승인 검토중
   * 액션아이템 6건 중 4건 카말 승인완료 / 2건 회신완료 5/29

 3. 쿼로스 프레임
 - 설계 및 전개도 협의 완료
  -> 고객사 설계 변경으로 2D 도면 검토 완료(4/14)
  -> 카우식 개발 점검 완료
 - 출하 : 업퍼 2대 6/6 출고, 로워 2대 6/8 출고예정
 - 1층 신규 부스 & 오븐 승인 진행중 (품질팀, LAM SE 니킬)

4. 내재화 프레임
  * 1세트 제작 및 승인서류 일정대로 진행 -> 민문주상무 고객 컨펌 후 3세트 제작진행
     - PM 김정준이사 - 화성/용인 내재화프레임 PM
 * TPM LAM 내부 우선순위 협의중(세이버 & 벡터코어), 텍슨은 동시 진행 요청중
   LAM프레임 담당은 동시진행 불가 입장
  1). SABRE 프레임 4종
    - 승인일정 : ~6/22(조찬형이사 계획수립)
    - LAN SE 니킬 C4에서 NC로 변경예정 회신(5/22) / CEFEM과 비교자료 작성 요청
      - #2 용접 진행중(용접후 FQC 검사후 도장진행, ~6/5)
  2) 벡터 코어 2종 (화성 신규 내재화 프레임) - BV2 8월 중순예상
    - STEEL 1종, AL 프레임 1종 / BV2 8월 중순 진행 예상(킥오프 전)
    - 원자재 구매 진행중(~6/9) / 내재화도면 설계중 (화성 심수영K, ~6/19)
    - 크로메이트 도금 (리치포트 : 가능) => 신규 프레임 도금라인 증설예정(흥옌)
   3) STRIP 프레임 2종 (용인)
    - 아크스프레이 테스트 진행중 ~6/12 / 외부 인증기관(베트남) 의뢰 예정(~6/17)
  4) MACH I VTM 1종
   - 메이져 모듈 신규 장비 8월말 승인에정
   - LMK 마크 1 프레임 승인순위 4위, 우선순위대로 승인 진행
"""

    result = parse_note(sample)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    print()
    print("=" * 60)
    print(f"카드 개수: {len(result)}")
    for c in result:
        sec_count = len(c['sections'])
        item_count = sum(len(s['items']) for s in c['sections'])
        print(f"  - [{c['title']}] 섹션 {sec_count}개, 항목 {item_count}개")
