from dotenv import load_dotenv
load_dotenv()

from openai import OpenAI
import json
import os

client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

SYSTEM_PROMPT = """당신은 반도체 사업부 임원 보고 비서입니다.
사장님은 1분 내에 핵심을 파악해야 합니다.

[신호등 분류 규칙 - 엄격히 준수]

RED (즉시 보고 필요) - 다음 중 하나라도 해당하면 무조건 RED:
- 일정 지연 발생 (납기 미달, 출하 지연)
- 자재 미입고 / 쇼티지 / 부족
- 매출에 부정적 영향 (출하 제한, 캔슬)
- 고객 컴플레인 / 클레임 / 품질 이슈
- 승인 거절 / 재작업 요구
- 사고 / 장비 고장 / 긴급 대응
- 계획 대비 50% 미만 실적

BLUE (진행 중 - 정상):
- 신규 RFQ / 견적 / 수주 진행 중
- 개발 / 검증 / 테스트 진행 중
- 승인 절차 정상 진행 중 (PDR/CDR/FAIR 등)
- LAP TEST / 양산 검증 중
- 계획 대비 50~99% 실적

BLACK (완료/안정):
- 양산 안정 진행
- 계획 100% 달성
- 출하 완료
- 최종 승인 완료 (수주 완료, 양산 승인 완료 등)
- 추가 조치 불필요

주의:
- "완료"라는 단어가 있으면 우선 BLACK 검토 (RED 아님!)
- "진행 중"은 보통 BLUE
- 새로운 좋은 소식 (수주, 승인 완료)은 절대 RED 아님

[그룹핑 규칙]
PPT 내용을 세부 제품 단위로 분리하세요.
같은 제품군 안에서도 다른 모델은 따로 카드를 만드세요.
예: EFEM, VTM, 파워박스, Aether GDX, CEFEM, 챔버, 엔클로저, 하바플레이트 등

[Headline 작성 규칙]
- 각 제품마다 반드시 다른 headline 작성 (똑같은 표현 절대 금지!)
- 가능하면 숫자 포함 (예: "5월 출하 4/8대 (50%)")
- 구체적인 상황 명시 (예: "로드락 ETA 미정")
- 25자 이내, 명사형으로 간결하게
- 좋은 소식: "수주 완료", "양산 승인" 등 명확하게

[출력 형식]
JSON 객체만 출력하세요. 다른 설명 절대 추가하지 마세요.
"""

USER_TEMPLATE = """다음 PPT 내용을 제품별로 분리·요약하세요.

{ppt_text}

반드시 아래 JSON 형식으로만 답하세요:

{{
  "report_meta": {{
    "title": "PPT 제목",
    "author": "작성자",
    "date": "YYYY-MM-DD",
    "report_family": "보고서_그룹키 (영문 소문자_언더바)",
    "report_week": "YYYY-W숫자"
  }},
  "products": [
    {{
      "name": "제품명",
      "category": "카테고리",
      "status": "RED 또는 BLUE 또는 BLACK",
      "headline": "이 제품만의 구체적 한 줄 요약 (25자 이내)",
      "kpis": [
        {{
          "label": "지표명",
          "value": "현재값",
          "target": "목표값",
          "status": "RED 또는 BLUE 또는 BLACK"
        }}
      ],
      "critical_issues": [
        {{
          "severity": "RED 또는 BLUE",
          "title": "이슈 제목",
          "detail": "구체적 상세 설명",
          "impact": "영향"
        }}
      ],
      "milestones": [
        {{
          "date": "YYYY-MM-DD",
          "event": "이벤트명",
          "status": "ON_TRACK 또는 DELAYED 또는 COMPLETED"
        }}
      ],
      "financials": {{
        "revenue": "금액",
        "note": "매출 관련 비고"
      }},
      "next_actions": ["조치1", "조치2"],
      "source_slide_numbers": [2, 3]
    }}
  ]
}}

[report_family 작성 가이드]
- 파워박스 진행현황 -> "powerbox"
- 메이져모듈 내재화프레임 진행현황 -> "major_module_frame"
- 반도체사업부 주간 진행현황 -> "semiconductor_weekly"
- 위에 없는 종류면 영문 소문자 + 언더바로 적절히 작성

[report_week 작성 가이드]
- 26년 5월 22일이고 22주차라면 -> "2026-W22"
- PPT 내용에서 주차 정보를 찾아 작성
"""


class ExecutiveSummarizer:
    def summarize(self, ppt_text: str) -> dict:
        response = client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": USER_TEMPLATE.format(ppt_text=ppt_text)},
            ],
            response_format={"type": "json_object"},
            temperature=0.1,
        )
        return json.loads(response.choices[0].message.content)
