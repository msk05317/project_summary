"""주차 소유 규칙 회귀 테스트.

읽는 쪽(main.py)과 쓰는 쪽(엑셀 임포터)이 주차를 서로 다른 달에 배정해서
2026년 W40 물량이 두 달 어디에도 안 잡히는 사고가 있었다.
규칙이 다시 갈라지면 여기서 걸린다.

    cd backend && python3 tests/test_week_calendar.py
"""
import datetime as _dt
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import week_calendar as wc
import plan_matrix_import as pm
import hrva_import as hv

YEARS = range(2024, 2031)


def test_known_months():
    """실제로 사고가 났던 2026년 8~10월."""
    assert wc.get_month_weeks("2026-08") == ["W32", "W33", "W34", "W35"]
    assert wc.get_month_weeks("2026-09") == ["W36", "W37", "W38", "W39", "W40"]
    assert wc.get_month_weeks("2026-10") == ["W41", "W42", "W43", "W44"]
    assert wc.month_of_week("W40", 2026) == "2026-09"


def _iso_year_of(y, m, week_label):
    """(연,월)의 주차 목록에 있는 라벨이 실제로 몇 년도 주차인지.

    12월은 다음 해 W01 을 가져갈 수 있다(말일이 3일 이상 걸치는 경우).
    라벨만 보면 그 해 W01 과 구분이 안 되므로 실제 날짜로 되돌려 확인한다.
    """
    n = int(week_label.lstrip("W"))
    first = _dt.date(y, m, 1)
    last = (_dt.date(y + 1, 1, 1) if m == 12 else _dt.date(y, m + 1, 1)) - _dt.timedelta(days=1)
    for cand in (y, y + 1, y - 1):
        try:
            mon = _dt.date.fromisocalendar(cand, n, 1)
        except ValueError:
            continue
        if mon <= last and mon + _dt.timedelta(days=6) >= first:
            return cand
    raise AssertionError(f"{y}-{m:02d} {week_label} 의 실제 연도를 못 찾음")


def test_every_week_owned_exactly_once():
    """(ISO 연도, 주차) 하나는 정확히 한 달에만 속해야 한다."""
    owner = {}
    for y in YEARS:
        for m in range(1, 13):
            for w in wc.get_month_weeks(f"{y}-{m:02d}"):
                key = (_iso_year_of(y, m, w), w)
                assert key not in owner, \
                    f"{key} 가 {owner.get(key)} 와 {y}-{m:02d} 에 중복 소유"
                owner[key] = f"{y}-{m:02d}"
    for y in YEARS:
        cnt = sum(1 for (iy, _w) in owner if iy == y)
        assert cnt >= 52, f"{y} 주차 수 {cnt}"


def test_bare_week_label_collides_in_december():
    """12월이 가져가는 다음 해 W01 은 라벨만으로는 그 해 W01 과 구분되지 않는다.

    weekly_plan 은 달로 한 번 더 나뉘어 있어 안전하지만,
    weekly_summary[그룹]["weeks"] 는 라벨만 쓰므로 12월 저장이 1월을 덮어쓴다.
    (결함 대장 7번 — 아직 미수정. 고치면 이 테스트를 뒤집을 것.)
    """
    dec = wc.get_month_weeks("2025-12")
    jan = wc.get_month_weeks("2025-01")
    overlap = set(dec) & set(jan)
    assert overlap == {"W01"}, f"예상과 다름: {overlap}"


def test_lookup_matches_listing():
    """month_of_week 가 가리키는 달의 주차 목록에 그 주차가 실제로 있어야 한다."""
    for y in YEARS:
        for n in range(1, 54):
            w = f"W{n:02d}"
            m = wc.month_of_week(w, y)
            if m is None:
                continue
            assert w in wc.get_month_weeks(m), f"{y} {w} → {m} 인데 목록에 없음"


def test_importers_agree_with_app():
    """임포터가 저장하는 달과 앱이 읽는 달이 같아야 한다. 이게 W40 사고의 본체다."""
    for y in YEARS:
        for n in range(1, 54):
            expected = wc.month_of_week(f"W{n:02d}", y)
            if expected is None:
                continue
            assert pm._month_of_week_iso(n, y) == expected, \
                f"plan_matrix {y} W{n:02d}: {pm._month_of_week_iso(n, y)} != {expected}"
            assert hv._month_of_week(n, y) == expected, \
                f"hrva_import {y} W{n:02d}: {hv._month_of_week(n, y)} != {expected}"


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
