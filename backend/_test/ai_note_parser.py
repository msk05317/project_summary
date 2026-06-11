import os
import json
from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()
client = OpenAI(api_key=os.environ.get("OPENAI_API_KEY"))

SYSTEM_PROMPT = """당신은 회사 임원에게 보고되는 주간 보고서를 구조화하는 도우미입니다.

입력으로 들어오는 자유 형식 텍스트를 다음 JSON 스키마로 변환하세요:

{
  "cards": [
    {
      "title": "프로젝트 이름",
      "sections": [
        {
          "title": "섹션 이름",
          "items": [
            {
              "type": "bullet | highlight | sub",
              "text": "항목 내용",
              "children": [ {"type": "sub", "text": "..."} ]
            }
          ]
        }
      ]
    }
  ]
}

규칙:
1. <텍스트>로 감싼 것은 새 카드(프로젝트 그룹)
2. 1. 2. 같은 번호는 카드 내부의 섹션
3. 1) 2) 처럼 들여쓰기 된 번호는 서브섹션. children으로 묶거나 별도 섹션으로 분리 — 가독성 우선
4. *로 시작하는 줄, 빨간색 강조하면 좋은 핵심 정보는 type: highlight
5. -, ▸ 일반 항목은 type: bullet
6. →, =>, 또는 들여쓰기 된 내용은 부모 항목의 children에 type: sub
7. 카드 제목·섹션 제목에서 번호 제거
8. 항목 텍스트에서 선행 기호 제거. 단, 본문 안의 → 같은 화살표는 유지
9. 의미는 절대 바꾸지 말 것
10. 빈 항목·중복 항목은 만들지 말 것

응답은 반드시 위 JSON 형식 한 객체만 출력. 마크다운, 코드블록, 설명 없이 JSON만 출력하세요."""


def parse_note_with_ai(text: str) -> dict:
    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": text},
        ],
        response_format={"type": "json_object"},
        temperature=0.1,
    )
    content = response.choices[0].message.content
    return json.loads(content)


SAMPLE = """<페러데이 4T>
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

if __name__ == "__main__":
    print("=== AI 호출 중 (5~15초 소요) ===\n")
    result = parse_note_with_ai(SAMPLE)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    print()
    print("=" * 60)
    cards = result.get("cards", [])
    print(f"카드 개수: {len(cards)}")
    for c in cards:
        sec_count = len(c.get("sections", []))
        item_count = sum(len(s.get("items", [])) for s in c.get("sections", []))
        print(f"  - [{c['title']}] 섹션 {sec_count}개, 항목 {item_count}개")
