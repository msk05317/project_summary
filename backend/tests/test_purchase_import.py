"""'월별 매입 현황 분석' 엑셀 읽기."""
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import purchase_import as PI  # noqa: E402


def t(name, cond):
    print(("  ok  " if cond else "  FAIL") + "  " + name)
    if not cond:
        raise SystemExit(1)


ROWS = [
    ["월별 매입 현황 분석", None, None, None, None, None, None, None],
    [None, None, "4월", "5월", "6월", "7월", "8월", "합계"],
    ["매출액", None, 1742300.4, 1512880.1, 1498640.2, 1533442.2, 1006562.6, 7293825.5],
    ["원소재", "매입액", 2600000, 1800000, 1500000, 1500000, 1180240.6, 8580240.6],
    [None, "지급액", 1700000, 1200000, 1100000, 1000000, 520110.2, 5520110.2],
    [None, "잔액", 900000, "(134,515.5)", 400000, 500000, 515850, 2181334.5],
    ["소모품", "매입액", 180000, 120000, 110000, 90000, 96320.4, 596320.4],
    [None, "지급액", 150000, 100000, 95000, 70000, 78440.5, 493440.5],
    [None, "잔액", 30000, 20000, 15000, 20000, 17879.9, 102879.9],
    ["기타 (약품, 포장재 등)", "매입액", 300000, 210000, 190000, 130000, 142880.1, 972880.1],
    [None, "지급액", 280000, 190000, 175000, 120000, 120660.3, 885660.3],
    [None, "잔액", "(1,012,867.4)", 20000, 15000, 10000, "(22,140.2)", None],
    ["외주", "매입액", 902420.1, 574310.7, 518660.4, 568473.2, 444958.1, 3008822.5],
    [None, "지급액", 350110, 312440, 330220, 434545, 180972.9, 1608287.9],
    [None, "잔액", 552310.1, 261870.7, 188440.4, 133928.2, 203450.1, 1339999.5],
    ["합계", "매입액", 3982420.1, 2704310.7, 2318660.4, 2288473.2, 1864399.2, 13158263.6],
    [None, "지급액", 2480110, 1802440, 1700220, 1624545, 900183.9, 8507498.9],
    ["선급금", None, 500000, 400000, 380000, 200000, 260514.3, 1740514.3],
    ["실지급액", None, 1980110, 1402440, 1320220, 1424545, 639669.6, 6767084.6],
    ["실비투자", None, None, None, None, None, None, None],
]


def make(path, rows=None, title="2026년 월별 매입 현황 분석"):
    import openpyxl
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = title
    for r in (rows or ROWS):
        ws.append(r)
    wb.save(path)


def main():
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "pcb.xlsx"
        make(p)
        got = PI.parse_workbook(p)

        t("5개 월", sorted(got["months"]) == ["2026-04", "2026-05", "2026-06",
                                             "2026-07", "2026-08"])
        t("못 알아본 줄 없음", got["warnings"] == [])
        t("항목 4개", [i["key"] for i in got["items"]] ==
          ["raw", "supply", "etc", "outsourcing"])
        t("항목 이름 유지",
          got["items"][2]["label"] == "기타 (약품, 포장재 등)")

        m8 = got["months"]["2026-08"]
        t("매출액", m8["revenue"] == 1006562.6)
        t("선급금", m8["prepaid"] == 260514.3)
        t("실지급액 (지급액과 헷갈리지 않는다)", m8["actual_paid"] == 639669.6)
        t("실비투자 빈 칸", m8["invest"] is None)
        it = {i["key"]: i for i in m8["items"]}
        t("원소재 매입", it["raw"]["buy"] == 1180240.6)
        t("원소재 잔액", it["raw"]["balance"] == 515850)
        t("괄호 음수 잔액", it["etc"]["balance"] == -22140.2)
        t("외주 지급", it["outsourcing"]["paid"] == 180972.9)

        t("합계 줄은 읽지 않는다",
          abs(sum(i["buy"] for i in m8["items"]) - 1864399.2) < 0.01)
        m5 = {i["key"]: i for i in got["months"]["2026-05"]["items"]}
        t("5월 원소재 음수 잔액", m5["raw"]["balance"] == -134515.5)

        # 빈 칸은 기존 값을 지우지 않는다
        old = {"2026-08": {"revenue": 999, "note": "손으로 적은 비고",
                           "invest": 123, "items": [
                               {"key": "raw", "label": "원소재", "buy": 1,
                                "paid": 2, "balance": 3}]},
               "2026-03": {"revenue": 555, "items": []}}
        merged = PI.merge_keep(old, got["months"])
        t("엑셀에 없는 달 유지", merged["2026-03"]["revenue"] == 555)
        t("비고 유지", merged["2026-08"]["note"] == "손으로 적은 비고")
        t("빈 실비투자가 기존 값을 안 지운다", merged["2026-08"]["invest"] == 123)
        t("엑셀 값이 덮어쓴다", merged["2026-08"]["revenue"] == 1006562.6)

        rows = PI.diff(old, got["months"])
        kinds = {r["month"]: r["kind"] for r in rows}
        t("4월은 새로", kinds["2026-04"] == "new")
        t("8월은 수정", kinds["2026-08"] == "update")

        # 연도가 넘어가는 표 (11월·12월·1월)
        p2 = Path(d) / "roll.xlsx"
        make(p2, rows=[
            [None, None, "11월", "12월", "1월"],
            ["매출액", None, 10, 20, 30],
            ["원소재", "매입액", 1, 2, 3],
        ], title="2026")
        got2 = PI.parse_workbook(p2)
        t("해 넘어가면 다음 해",
          sorted(got2["months"]) == ["2026-11", "2026-12", "2027-01"])

        # 표가 없으면 에러
        p3 = Path(d) / "no.xlsx"
        make(p3, rows=[["아무것도", "없음"], [1, 2]], title="빈시트")
        try:
            PI.parse_workbook(p3)
            t("표 없으면 에러", False)
        except ValueError:
            t("표 없으면 에러", True)

    print("test_purchase_import: 전부 통과")


if __name__ == "__main__":
    main()
