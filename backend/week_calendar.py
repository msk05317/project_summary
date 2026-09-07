"""주차 ↔ 월 소유 규칙 단일 진입점.

한 ISO 주차는 반드시 한 달에만 속한다. 규칙은 세 줄이다.

  1) 기본: 그 주 목요일이 속한 달              (2026년 8월 = W32~W35)
  2) 말일이 3일 이상 걸친 주는 그 달이 가져간다  (2026년 9월 = W36~W40)
  3) 앞 달이 가져간 주차는 다음 달에서 뺀다      (2026년 10월 = W41~W44)

이 파일이 생긴 이유:
main.py 는 위 규칙대로 읽는데, 엑셀 임포터들은 (1)만 보고 저장하고 있었다.
2026년에는 W40 하나가 어긋났고, W40 물량이 weekly_plan["2026-10"]["W40"] 에
쌓이는 바람에 9월(그 자리를 안 봄)에도 10월(W41부터 봄)에도 잡히지 않았다.
규칙 사본이 여러 개라서 생긴 문제이므로, 앞으로는 읽는 쪽도 쓰는 쪽도 여기만 쓴다.
"""

from __future__ import annotations

import datetime as _dt


def month_weeks_base(y: int, m: int) -> list:
    """규칙 (1)+(2) 만 적용한 주차 목록. 앞 달과 겹칠 수 있다."""
    first = _dt.date(y, m, 1)
    last = (_dt.date(y + 1, 1, 1) if m == 12 else _dt.date(y, m + 1, 1)) - _dt.timedelta(days=1)
    weeks = []
    seen = set()
    cur = first
    while cur <= last:
        if cur.weekday() == 3:  # 목요일
            _, iso_week, _ = cur.isocalendar()
            key = f"W{iso_week:02d}"
            if key not in seen:
                seen.add(key)
                weeks.append(key)
        cur += _dt.timedelta(days=1)

    _, w_last, _ = last.isocalendar()
    key_last = f"W{w_last:02d}"
    if key_last not in seen:
        mon = last - _dt.timedelta(days=last.weekday())
        days = sum(1 for i in range(7) if first <= mon + _dt.timedelta(days=i) <= last)
        if days >= 3:
            weeks.append(key_last)
    return weeks


def get_month_weeks(month: str) -> list:
    """'2026-09' → ['W36','W37','W38','W39','W40']."""
    y, m = map(int, str(month).split("-"))
    weeks = month_weeks_base(y, m)
    py, pm = (y - 1, 12) if m == 1 else (y, m - 1)
    prev = set(month_weeks_base(py, pm))
    while weeks and weeks[0] in prev:
        weeks = weeks[1:]
    return weeks


def month_of_week(week_label, year=None):
    """'W40' → 그 주차를 소유한 'YYYY-MM'. get_month_weeks 와 항상 일치한다."""
    if week_label in (None, ""):
        return None
    try:
        n = int(str(week_label).upper().lstrip("W"))
    except Exception:
        return None
    if not (1 <= n <= 53):
        return None
    if year is None:
        year = _dt.date.today().year

    for _y in (year, year - 1):
        try:
            thu = _dt.date.fromisocalendar(_y, n, 4)
        except Exception:
            continue
        key = f"W{n:02d}"
        iso_month = f"{thu.year}-{thu.month:02d}"
        # 앞 달이 이 주차를 가져갔으면(2026년 9월의 W40 처럼) 그 달을 돌려준다
        py, pm = (thu.year - 1, 12) if thu.month == 1 else (thu.year, thu.month - 1)
        prev_month = f"{py}-{pm:02d}"
        try:
            if key in get_month_weeks(prev_month):
                return prev_month
        except Exception:
            pass
        return iso_month
    return None


def month_of_week_no(week_no, year):
    """주차 '번호'로 받는 형태. 임포터들이 쓰던 시그니처와 맞춘다."""
    return month_of_week(f"W{int(week_no):02d}", year)
