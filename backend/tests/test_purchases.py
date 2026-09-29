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


    # 8. 해외/국내 · 재고 · 비고 (v2)
    v2 = P.put_division({}, "pcb", {"currency": "USD", "months": {"2026-08": {
        "revenue": {"total": 7610417, "overseas": 476059, "domestic": 7134358},
        "items": [{"key": "raw", "label": "원소재",
                   "buy": {"total": 8776516, "overseas": 3510607, "domestic": 5265910},
                   "paid": {"total": 3385301, "overseas": 2166593, "domestic": 1218708},
                   "balance": {"total": 4307358, "overseas": 2295111, "domestic": 2012247},
                   "note": "· EMC PO 취소\n· 생익 PO 취소"}],
        "stock": {"available": {"value": {"total": 1833674}},
                  "dead": {"value": {"total": 1889828}, "note": "재고금액에서 제외"},
                  "wip": {"value": {"total": 2084915}},
                  "finished": {"value": {"total": 2286364}, "note": "실물 확인 필요"}},
        "receivable": {"total": 1112019, "domestic": 1112019},
        "total_buy": {"total": 6953311, "overseas": 1419098, "domestic": 5534213}}}})

    a = P.for_app(v2, "pcb")["months"][0]
    t("합계 매출", a["revenue"] == 7610417)
    t("매출 대비 매입비율 자동", a["buy_over_revenue"] == 91.4)
    o = P.for_app(v2, "pcb", "overseas")["months"][0]
    t("해외 매출", o["revenue"] == 476059)
    t("해외 비율 298%", o["buy_over_revenue"] == 298.1)
    d = P.for_app(v2, "pcb", "domestic")["months"][0]
    t("국내 비율 78%", d["buy_over_revenue"] == 77.6)

    t("비고는 줄바꿈을 지킨다",
      a["items"][0]["notes"]["balance"].count("\n") == 1)
    t("재고 4줄", [x["label"] for x in a["stock"]] ==
      ["가용 원재고", "불용 원자재", "재공 재고", "완제품 재고"])
    t("재공+완제품 합계", a["stock_total"] == 2084915 + 2286364)
    t("불용은 합계에서 뺀다", a["stock_total"] != sum(
        x["value"] for x in a["stock"] if x["value"] is not None))
    t("미수금 해외는 미입력", o["receivable"] is None)
    t("미수금 국내", d["receivable"] == 1112019)

    # 안 적은 지역은 0 이 아니라 '미입력' 로 남는다
    only_total = P.put_division({}, "pcb", {"months": {"2026-08": {
        "revenue": 1000, "items": [{"key": "raw", "label": "원소재",
                                    "buy": 500, "paid": 200}]}}})
    t("숫자 하나면 합계로 읽는다", P.for_app(only_total, "pcb")["months"][0]["buy"] == 500)
    t("안 적은 해외는 채워진 적 없음",
      P.for_app(only_total, "pcb")["regions_filled"]["overseas"] is False)
    t("해외 탭은 비어 보인다",
      P.for_app(only_total, "pcb", "overseas")["months"][0]["items"] == [])

    # 누적: 재고는 더하지 않고 마지막 달을 쓴다 (시점 값이라 더하면 없는 숫자가 된다)
    two = P.put_division({}, "pcb", {"months": {
        "2026-07": {"items": [{"key": "raw", "label": "원소재", "buy": 100, "paid": 40}],
                    "stock": {"wip": {"value": 10}}},
        "2026-08": {"items": [{"key": "raw", "label": "원소재", "buy": 200, "paid": 60}],
                    "stock": {"wip": {"value": 30}}}}})
    tv = P.for_app(two, "pcb")["total"]
    t("누적 매입은 더한다", tv["buy"] == 300)
    t("누적 재고는 마지막 달", tv["stock_total"] == 30)


    # 9. 저장 → 다시 읽기 → 저장을 되풀이해도 아무것도 안 사라진다
    #    (재고를 리스트로 저장해 놓고 dict 만 읽던 버그가 여기서 잡혔다)
    import copy as _copy
    st = _copy.deepcopy(P.for_admin(v2, "pcb")["months"])
    round1 = P.put_division(v2, "pcb", {"currency": "USD", "months": st})
    r1 = round1["divisions"]["pcb"]["months"]["2026-08"]
    t("왕복: 해외 값 유지", r1["items"][0]["buy"]["overseas"] == 3510607)
    t("왕복: 비고 줄 유지",
      r1["notes"]["item:raw:balance"].count("\n") == 1)
    t("왕복: 재고 4줄 유지",
      [x["key"] for x in r1["stock"]] == ["available", "dead", "wip", "finished"])
    t("왕복: 재고 값 유지", r1["stock"][2]["value"]["total"] == 2084915)
    t("왕복: 재고 비고 유지", r1["notes"]["stock:finished"] == "실물 확인 필요")
    t("왕복: 미수금 유지", r1["receivable"]["domestic"] == 1112019)
    t("왕복: 총 매입액 유지", r1["total_buy"]["overseas"] == 1419098)

    again = round1
    for _ in range(3):
        again = P.put_division(again, "pcb", {"currency": "USD",
                                              "months": _copy.deepcopy(
                                                  P.for_admin(again, "pcb")["months"])})
    r3 = again["divisions"]["pcb"]["months"]["2026-08"]
    t("네 번 저장해도 그대로", r3["stock"][2]["value"]["domestic"] is None
      or r3["stock"][2]["value"]["total"] == 2084915)
    t("네 번 저장해도 비고 그대로",
      r3["notes"]["item:raw:balance"].count("\n") == 1)


    # 10. 비고는 줄마다 하나 (매출액·매입액·지급액·잔액에 각각)
    nv = P.put_division({}, "pcb", {"months": {"2026-08": {
        "revenue": {"total": 100},
        "items": [{"key": "raw", "label": "원소재",
                   "buy": {"total": 10}, "paid": {"total": 4}, "balance": {"total": 6},
                   "note": "옛 모양 비고"}],
        "stock": {"wip": {"value": {"total": 1}, "note": "옛 재고 비고"}},
        "notes": {"revenue": "매출 줄", "item:raw:buy": "매입 줄\n둘째 줄",
                  "item:raw:paid": "지급 줄", "sum:buy": "합계 줄",
                  "stock:dead": "재고 줄", "월:이상한키": "버려야 함"}}}})
    n = nv["divisions"]["pcb"]["months"]["2026-08"]["notes"]
    t("줄별 비고 저장", n["revenue"] == "매출 줄" and n["item:raw:paid"] == "지급 줄")
    t("합계 줄에도 붙는다", n["sum:buy"] == "합계 줄")
    t("옛 항목 비고는 잔액 줄로", n["item:raw:balance"] == "옛 모양 비고")
    t("옛 재고 비고도 옮겨짐", n["stock:wip"] == "옛 재고 비고")
    t("이상한 키는 버린다", "월:이상한키" not in n)

    nva = P.for_app(nv, "pcb")["months"][0]
    t("앱: 항목 비고 3칸",
      nva["items"][0]["notes"] == {"buy": "매입 줄\n둘째 줄", "paid": "지급 줄",
                                   "balance": "옛 모양 비고"})
    t("앱: 재고 비고", [x["note"] for x in nva["stock"] if x["key"] == "dead"] == ["재고 줄"])
    t("앱: 월 전체 비고 map", nva["notes"]["revenue"] == "매출 줄")

    # 왕복해도 안 사라진다
    import copy as _c2
    rt = P.put_division(nv, "pcb", {"months": _c2.deepcopy(P.for_admin(nv, "pcb")["months"])})
    t("왕복: 줄별 비고 유지",
      rt["divisions"]["pcb"]["months"]["2026-08"]["notes"]["item:raw:buy"].count("\n") == 1)


    # 11. 누적(summary) — 달을 더하지 않고 표에 적힌 합계를 쓴다
    #
    # 이 엑셀은 매출 합계가 4~8월 합보다 크다(31만). 어느 쪽이 맞는지는
    # 표를 쓴 사람이 안다. 그리고 해외/국내는 누적에만 있다.
    sv = P.put_division({}, "pcb", {
        "currency": "USD",
        "months": {
            "2026-07": {"revenue": {"total": 1438651.3},
                        "items": [{"key": "raw", "label": "원소재",
                                   "buy": {"total": 3873320.6},
                                   "paid": {"total": 182815.3},
                                   "balance": {"total": 3690505.3}}]},
            "2026-08": {"revenue": {"total": 1006562.6},
                        "items": [{"key": "raw", "label": "원소재",
                                   "buy": {"total": 1427312.2},
                                   "paid": {"total": 946360.5},
                                   "balance": {"total": 480951.7}}]},
        },
        "summary": {
            "revenue": {"total": 7610417.5, "overseas": 476059.0,
                        "domestic": 7134358.4},
            "items": [{"key": "raw", "label": "원소재",
                       "buy": {"total": 8776516.3, "overseas": 3510606.5,
                               "domestic": 5265909.8},
                       "paid": {"total": 3385301.2, "overseas": 2166592.8,
                                "domestic": 1218708.4},
                       "balance": {"total": 4307358.0, "overseas": 2295111.0,
                                   "domestic": 2012247.0}}],
            "stock": [{"key": "wip", "value": {"total": 2084915.0,
                                               "overseas": 806184.0,
                                               "domestic": 1278731.0}},
                      {"key": "finished", "value": {"total": 2286364.0,
                                                    "overseas": 955765.0,
                                                    "domestic": 1330599.0}}],
            "receivable": {"total": 1112019.0, "overseas": 0, "domestic": 1112019.0},
            "total_buy": {"total": 6953310.6, "overseas": 1419097.6,
                          "domestic": 5534213.0},
            "notes": {"ratio": "비율 줄 비고", "month": "추가 분석 필요"},
        },
    })
    sb = sv["divisions"]["pcb"]
    t("누적은 따로 저장", isinstance(sb.get("summary"), dict))
    t("누적 구간", sb["summary"]["from"] == "2026-07" and sb["summary"]["to"] == "2026-08")
    t("비율 줄 비고도 남는다", sb["summary"]["notes"]["ratio"] == "비율 줄 비고")

    sa = P.for_app(sv, "pcb")
    t("누적은 표의 값", sa["total"]["revenue"] == 7610417.5)
    t("달 합(2,445,213.9)이 아니다", sa["total"]["revenue"] != 2445213.9)
    t("어디서 온 값인지 말해 준다", sa["total"]["source"] == "sheet")
    t("누적 구간 표시", sa["total"]["range"] == "7월~8월")
    t("누적 미수금", sa["total"]["receivable"] == 1112019.0)
    t("누적 재공+완제품", sa["total"]["stock_total"] == 4371279.0)
    t("매출 대비 매입 91.4%", sa["total"]["buy_over_revenue"] == 91.4)
    t("누적 비고", sa["total"]["note"] == "추가 분석 필요")
    t("has_summary", sa["has_summary"] is True)

    so = P.for_app(sv, "pcb", "overseas")
    t("해외 누적 매출", so["total"]["revenue"] == 476059.0)
    t("해외 비율 298.1%", so["total"]["buy_over_revenue"] == 298.1)
    sd = P.for_app(sv, "pcb", "domestic")
    t("국내 비율 77.6%", sd["total"]["buy_over_revenue"] == 77.6)

    # 해외/국내가 달별로는 없다 — 앱이 달 탭을 흐리게 할 수 있게 갈라서 준다
    t("달별 해외는 비어 있다", sa["months_regions_filled"]["overseas"] is False)
    t("누적 해외는 있다", sa["summary_regions_filled"]["overseas"] is True)
    t("해외 탭 자체는 켠다", sa["regions_filled"]["overseas"] is True)

    # summary 를 안 보내면 있던 누적을 지킨다 (화면이 안 들고 있을 수 있다)
    keep = P.put_division(sv, "pcb", {"months": P.for_admin(sv, "pcb")["months"]})
    t("안 보내면 누적 유지",
      keep["divisions"]["pcb"]["summary"]["revenue"]["total"] == 7610417.5)
    # 빈 누적을 명시해서 보내면 지운다
    gone = P.put_division(sv, "pcb", {"months": {}, "summary": {}})
    t("빈 누적을 보내면 지운다", "summary" not in gone["divisions"]["pcb"])

    # 왕복 — for_admin 이 누적을 같이 주고, 그걸 그대로 저장해도 같다
    rt2 = P.put_division(sv, "pcb", {
        "months": P.for_admin(sv, "pcb")["months"],
        "summary": P.for_admin(sv, "pcb")["summary"]})
    t("왕복: 누적 해외 유지",
      rt2["divisions"]["pcb"]["summary"]["items"][0]["buy"]["overseas"] == 3510606.5)
    t("왕복: 누적 재고 유지",
      rt2["divisions"]["pcb"]["summary"]["stock"][2]["value"]["total"] == 2084915.0)

    # 누적이 없으면 예전처럼 달을 더한다
    nosum = P.put_division({}, "pcb", {"months": {
        "2026-07": {"revenue": {"total": 10}},
        "2026-08": {"revenue": {"total": 20}}}})
    na = P.for_app(nosum, "pcb")
    t("누적 없으면 달을 더한다",
      na["total"]["revenue"] == 30 and na["total"]["source"] == "sum")

    print("test_purchases: 전부 통과")


if __name__ == "__main__":
    main()
