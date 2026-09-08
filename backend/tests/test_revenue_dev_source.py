"""개발 주차값을 '모델별 입력'과 '그룹 총계' 중 어디서 읽는지 고정한다.

이 판단이 뒤집히면 화면에서는 그냥 숫자가 조금 작게 보일 뿐이라 눈에 안 띈다.
실제로 파워박스 9월 실적이 52대 대신 51대로 나오고 있었다.

main.py 를 통째로 import 하면 FastAPI 가 뜨므로, 함수 정의만 뽑아 실행한다.
함수 이름이 바뀌거나 사라지면 여기서 먼저 걸린다.

    cd backend && python3 tests/test_revenue_dev_source.py
"""
import re
import sys
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
SRC = (BASE / "main.py").read_text(encoding="utf-8")

_m = re.search(r"^def _dev_weeks_from_models\(.*?(?=\n\n\n)", SRC, re.S | re.M)
assert _m, "main.py 에서 _dev_weeks_from_models 를 찾지 못했습니다"
_ns = {}
exec(_m.group(0), _ns)
pick = _ns["_dev_weeks_from_models"]

EMPTY = {w: {"plan": 0, "actual": 0} for w in ("W36", "W37", "W38")}
GROUP = {"weeks": {"W36": {"plan": 8, "actual": 9}, "W37": {"plan": 6, "actual": 42}}}


def test_모델에_값이_있으면_모델이_정본():
    """파워박스: 853-043648-115 의 W36 실적 1대가 살아 있어야 한다."""
    weeks = dict(EMPTY, **{"W36": {"plan": 0, "actual": 1}})
    assert pick(weeks, GROUP) is True


def test_계획만_있어도_모델이_정본():
    """실적이 아직 0 이어도 계획이 들어와 있으면 모델 쪽을 본다."""
    weeks = dict(EMPTY, **{"W38": {"plan": 50, "actual": 0}})
    assert pick(weeks, GROUP) is True


def test_모델이_전부_0이면_그룹_총계를_쓴다():
    """하바플레이트: 개발 모델 40종에 주차 칸만 있고 값은 전부 0 이다."""
    assert pick(EMPTY, GROUP) is False


def test_그룹_총계가_없으면_언제나_모델():
    assert pick(EMPTY, {}) is True
    assert pick(EMPTY, {"weeks": {}}) is True
    assert pick({}, None) is True


if __name__ == "__main__":
    fails = 0
    for name, fn in sorted(globals().items()):
        if not name.startswith("test_"):
            continue
        try:
            fn()
            print(f"  PASS  {name}")
        except AssertionError as e:
            fails += 1
            print(f"  FAIL  {name}\n        {e}")
    print(f"\n{'실패 ' + str(fails) + '건' if fails else '전부 통과'}")
    sys.exit(1 if fails else 0)
