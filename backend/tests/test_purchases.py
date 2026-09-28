"""매입 현황 — 잔액은 적힌 값, 빈 칸은 계산."""
import json
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import purchases as P  # noqa: E402


def t(name, cond):
    print(("  ok  " if cond else "  FAIL") + "  " + name)
    if not cond:
        raise SystemExit(1)


def main():
    # 1. 괄호 음수 · 콤마 · $ 를 읽는다
    t("(1,234.5) = -1234.5", P._num("(1,234.5)") == -1234.5)
    t("$1,006,562.6", P._num("$1,006,562.6") == 1006562.6)
    t("빈 칸은 None", P._num("") is None and P._num(None) is None)

    # 2. 잔액은 적힌 값을 쓴다 (매입-지급과 달라도)
    data = P.put_division({}, "pcb", {
        "currency": "USD",
        "months": {
            "2026-08": {
                "revenue": 1006562.6,
                "items": [
                    {"key": "raw", "label": "원소재", "buy": 1000, "paid": 400, "balance": 500},
                    {"key": "supply", "label": "소모품", "buy": 200, "paid": 100},
                ],
                "prepaid": 50, "actual_paid": 500,
            }
        },
    })
    view = P.for_app(data, "pcb")
    m = view["months"][0]
    t("적힌 잔액 유지", m["items"][0]["balance"] == 500 and not m["items"][0]["balance_auto"])
    t("빈 잔액은 매입-지급", m["items"][1]["balance"] == 100 and m["items"][1]["balance_auto"])
    t("월 합계 매입", m["buy"] == 1200)
    t("월 합계 잔액 = 항목 합", m["balance"] == 600)
    t("지급률", m["pay_rate"] == round(500 / 1200 * 100, 1))
    t("지급내역 합계", m["payment"]["total"] == 550)
    t("실비투자 미입력은 None", m["payment"]["invest"] is None)

    # 3. 누적
    data = P.put_division(data, "pcb", {
        "currency": "USD",
        "months": {
            "2026-07": {"revenue": 100, "items": [
                {"key": "raw", "label": "원소재", "buy": 500, "paid": 300, "balance": 150}]},
            "2026-08": data["divisions"]["pcb"]["months"]["2026-08"],
        },
    })
    view = P.for_app(data, "pcb")
    t("월 정렬", [x["month"] for x in view["months"]] == ["2026-07", "2026-08"])
    t("최신월", view["latest"] == "2026-08")
    tot = view["total"]
    t("누적 매입", tot["buy"] == 1700)
    t("누적 잔액", tot["balance"] == 750)
    t("누적 항목 합쳐짐", len(tot["items"]) == 2)
    raw = [i for i in tot["items"] if i["key"] == "raw"][0]
    t("누적 원소재 매입", raw["buy"] == 1500)
    t("누적 범위", tot["range"] == "7월~8월")

    # 4. 데이터 없는 사업부
    empty = P.for_app(data, "ess")
    t("빈 사업부", empty["has_data"] is False and empty["months"] == [])
    t("빈 사업부 누적 0", empty["total"]["buy"] == 0)

    # 5. 저장/불러오기 왕복
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "purchases.json"
        P.save(p, data)
        back = P.load(p)
        t("왕복 후 동일", P.for_app(back, "pcb")["total"]["buy"] == 1700)
        t("updated_at 기록", bool(json.loads(p.read_text(encoding="utf-8"))["updated_at"]))

    # 6. 이상한 값은 버린다
    junk = P.normalize({"divisions": {"pcb": {"months": {"2026-13": {}, "aaa": {}, "2026-08": {}}}}})
    t("잘못된 월 제거", list(junk["divisions"]["pcb"]["months"]) == ["2026-08"])
    t("항목 없으면 기본 4개", len(junk["divisions"]["pcb"]["months"]["2026-08"]["items"]) == 4)


    # 7. 세 칸이 다 0인 항목은 앱에서 뺀다 (admin 입력 칸은 남는다)
    z = P.put_division({}, "pcb", {"currency": "USD", "months": {"2026-08": {
        "revenue": 100,
        "items": [
            {"key": "raw", "label": "원소재", "buy": 1000, "paid": 400, "balance": 500},
            {"key": "g2", "label": "조립자재", "buy": 0, "paid": 0, "balance": 0},
            {"key": "supply", "label": "소모품", "buy": 200, "paid": 100},
        ],
        "prepaid": 10, "actual_paid": 20}}})
    zv = P.for_app(z, "pcb")
    t("0 만 있는 항목은 앱에서 뺀다",
      [i["label"] for i in zv["months"][0]["items"]] == ["원소재", "소모품"])
    t("누적에서도 뺀다",
      [i["label"] for i in zv["total"]["items"]] == ["원소재", "소모품"])
    t("합계는 그대로", zv["months"][0]["buy"] == 1200)
    t("admin 입력 칸은 남는다",
      [i["label"] for i in P.for_admin(z, "pcb")["months"]["2026-08"]["items"]]
      == ["원소재", "조립자재", "소모품"])
    # 한 칸이라도 값이 있으면 남는다
    z2 = P.put_division({}, "pcb", {"currency": "USD", "months": {"2026-08": {
        "items": [{"key": "g2", "label": "조립자재", "buy": 0, "paid": 0,
                   "balance": -5}]}}})
    t("잔액만 있어도 남는다",
      len(P.for_app(z2, "pcb")["months"][0]["items"]) == 1)

    print("test_purchases: 전부 통과")


if __name__ == "__main__":
    main()
