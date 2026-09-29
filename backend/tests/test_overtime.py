"""전사 잔업·특근 — 주 단위, 'X'는 0이 아니다.

    python3 backend/tests/test_overtime.py

여기서 지키려는 것 세 가지:
  1. 'X'(해당 없음)를 0으로 세지 않는다. 일요일 잔업, 평일 특근이 X다.
  2. 사업부 키가 한글이어도 살아남는다 — 한 번 16개 중 3개만 남은 적이 있다.
  3. 반올림이 엑셀과 같다(0.5는 올림). 사업부마다 1명씩 어긋나면
     전사 합계가 엑셀과 안 맞는다.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import overtime as OT  # noqa: E402

ok = 0


def t(name, cond):
    global ok
    print(("  ok  " if cond else "  FAIL") + "  " + name)
    if not cond:
        raise SystemExit(1)
    ok += 1


def day(avail, direct, indirect, ot=None, sp=None, day_=None, night=None):
    """요일 한 칸 만들기. ot/sp 는 (전체, 직접, 간접) 또는 None(=X)."""
    d = {
        "headcount": {"total": avail, "day": day_, "night": night},
        "available": {"total": avail, "day": day_, "night": night},
        "direct": {"total": direct}, "indirect": {"total": indirect},
    }
    for key, v in (("overtime", ot), ("special", sp)):
        d[key] = {"people": {"total": None, "direct": None, "indirect": None}
                  if v is None else
                  {"total": v[0], "direct": v[1], "indirect": v[2]}}
    return d


# PCB W39 실제 값 (전사_사업부별_W39_주간잔특근_취합)
PCB_OT = [(79, 78, 1), (98, 93, 5), (105, 104, 1),
          (127, 122, 5), (117, 112, 5), (119, 117, 2)]
PCB_SUN = (88, 86, 2)


def pcb_days():
    out = {}
    for i, d in enumerate(("mon", "tue", "wed", "thu", "fri", "sat")):
        out[d] = day(441, 378, 63, ot=PCB_OT[i], day_=300, night=141)
    out["sun"] = day(441, 378, 63, sp=PCB_SUN, day_=300, night=141)
    return out


def main():
    # 1. 'X' 는 None 이고 0 과 다르다
    t("'X' 는 None", OT.num("X") is None and OT.num("x") is None)
    t("0 은 0", OT.num(0) == 0.0 and OT.num("0") == 0.0)
    t("빈 칸은 None", OT.num("") is None and OT.num(None) is None)
    t("주차 형식", OT.week_key("2026-W39") == "2026-W39"
      and OT.week_key("2026-W54") == "" and OT.week_key("W39") == "")

    # 2. 사업부 한 곳 — 잔업은 월~토, 특근은 일요일만
    data = OT.put_week({}, "2026-W39", {
        "range": "9/21~9/27",
        "divisions": {"pcb": {"label": "PCB", "days": pcb_days(), "check": "OK"}},
        "order": ["pcb"]})
    d = OT.for_division(data, "pcb")
    s = d["summary"]
    t("가용 441", s["available"]["total"] == 441)
    t("야간비율 32.0%", s["night_rate"] == 0.3197)
    t("잔업 인원 108 (월~토 평균)", s["overtime"]["people"]["total"] == 108)
    t("잔업률 24.4%", s["overtime"]["rate"]["total"] == 0.2438)
    t("직접 잔업률 27.6%", s["overtime"]["rate"]["direct"] == 0.276)
    t("간접 잔업률 5.0%", s["overtime"]["rate"]["indirect"] == 0.0503)
    t("특근 인원 88 (일요일)", s["special"]["people"]["total"] == 88)
    t("특근률 20.0%", s["special"]["rate"]["total"] == 0.1995)
    t("직접 특근률 22.8%", s["special"]["rate"]["direct"] == 0.2275)

    # 일요일 잔업을 0 으로 세면 108 이 아니라 93 이 된다
    t("일요일은 잔업 평균에서 빠진다", s["overtime"]["people"]["total"] != 93)
    t("요일 7개", len(d["by_day"]) == 7)
    t("일요일만 특근으로 표시",
      [x["kind"] for x in d["by_day"]] == ["overtime"] * 6 + ["special"])
    t("목요일이 제일 높다",
      max(d["by_day"][:6], key=lambda x: x["rate"])["label"] == "목")

    # 3. 한글 키가 살아남는다 (16개 중 3개만 남은 적이 있다)
    many = {("사업부%d" % i): {"label": "사업부%d" % i,
                              "days": {"mon": day(10, 8, 2, ot=(5, 4, 1))}}
            for i in range(1, 17)}
    many["통합보전자동화tms"] = {"label": "통합보전·자동화·TMS",
                                "days": {"mon": day(10, 8, 2, ot=(1, 1, 0))}}
    w2 = OT.put_week({}, "2026-W39", {"divisions": many})
    t("한글 사업부 키 유지",
      len(w2["weeks"]["2026-W39"]["divisions"]) == 17)
    t("한글·영문 섞인 키도 유지",
      "통합보전자동화tms" in w2["weeks"]["2026-W39"]["divisions"])

    # 4. 전사는 가중평균 — 인원 30명과 3,000명을 같은 무게로 세지 않는다
    two = OT.put_week({}, "2026-W39", {"divisions": {
        "큰곳": {"label": "큰곳", "days": {"mon": day(1000, 900, 100, ot=(900, 850, 50))}},
        "작은곳": {"label": "작은곳", "days": {"mon": day(10, 8, 2, ot=(1, 1, 0))}}}})
    v = OT.for_app(two)
    t("전사 = 901/1010", v["total"]["overtime"]["rate"]["total"] == 0.8921)
    t("단순평균(45.5%)이 아니다", v["total"]["overtime"]["rate"]["total"] > 0.8)
    t("초과 1곳 · 이하 1곳",
      v["counts"]["over"] == 1 and v["counts"]["under"] == 1)
    t("높은 순으로 정렬", [x["key"] for x in v["items"]] == ["큰곳", "작은곳"])

    # 5. 반올림은 엑셀과 같게 (0.5 올림)
    t("0.5 는 올린다", OT._r(164.5) == 165 and OT._r(107.5) == 108)
    t("음수도 절대값 기준 올림", OT._r(-0.5) == -1)

    # 6. 전주 대비
    prev = OT.put_week(data, "2026-W38", {"divisions": {
        "pcb": {"label": "PCB", "days": {
            "mon": day(441, 378, 63, ot=(73, 70, 3), day_=300, night=141)}}}})
    pv = OT.for_app(prev, "2026-W39")
    t("직전 주를 찾는다", pv["prev_week"] == "2026-W38")
    t("증감이 붙는다", pv["items"][0]["delta"] is not None)
    t("올랐다", pv["items"][0]["delta"] > 0)
    t("전주가 없으면 증감 없음",
      OT.for_app(prev, "2026-W38")["items"][0]["delta"] is None)

    # 7. 왕복 — 저장하고 다시 읽어도 X 가 0 이 되지 않는다
    rt = OT.normalize(data)
    sun = rt["weeks"]["2026-W39"]["divisions"]["pcb"]["days"]["sun"]
    t("왕복: 일요일 잔업은 여전히 None",
      sun["overtime"]["people"]["total"] is None)
    t("왕복: 일요일 특근은 88", sun["special"]["people"]["total"] == 88.0)
    again = OT.for_division(OT.normalize(rt), "pcb")["summary"]
    t("왕복: 잔업률 그대로", again["overtime"]["rate"]["total"] == 0.2438)

    # 8. 비고·일치확인·확인사항은 버리지 않는다
    wn = OT.put_week({}, "2026-W39", {
        "issues": ["PRESS — 파일 2개 제출"],
        "divisions": {"네트워크": {"label": "네트워크",
                                   "days": {"mon": day(10, 8, 2, ot=(5, 4, 1))},
                                   "note": "직접+간접 합 불일치",
                                   "check": "확인필요"}}})
    av = OT.for_app(wn)
    t("확인필요를 센다", av["counts"]["check"] == 1)
    t("비고가 항목에 붙는다", av["items"][0]["note"] == "직접+간접 합 불일치")
    t("확인사항이 남는다", av["issues"] == ["PRESS — 파일 2개 제출"])
    t("이상한 check 는 버린다",
      OT.normalize_division({"check": "몰라"})["check"] == "")

    # 9. 주차 하나만 바꾸고 나머지는 둔다
    keep = OT.put_week(prev, "2026-W39", {"divisions": {}})
    t("다른 주는 그대로", "2026-W38" in keep["weeks"])
    t("바꾼 주만 비었다",
      keep["weeks"]["2026-W39"]["divisions"] == {})
    try:
        OT.put_week({}, "W39", {})
        t("이상한 주차는 거부", False)
    except ValueError:
        t("이상한 주차는 거부", True)


    # 10. 검산은 요일 원본값으로 — 주 평균으로 하면 멀쩡한 곳이 틀려 보인다
    bad = {"days": {
        "mon": day(100, 70, 25, ot=(50, 45, 5)),          # 직접+간접=95 ≠ 가용 100
        "sun": day(100, 70, 30, sp=(40, 30, 5), day_=60, night=35)}}  # 주간+야간=95
    au = {x["code"]: x for x in OT.audit_division(bad)}
    t("직접+간접≠가용 을 잡는다", "avail_kind" in au)
    t("주간+야간≠가용 을 잡는다", "avail_shift" in au)
    t("특근 직접+간접≠전체 를 잡는다", "special_kind" in au)
    t("어느 요일인지 말해 준다", au["avail_shift"]["days"] == ["sun"])
    t("몇 명 차이인지 말해 준다", au["avail_shift"]["min"] == -5)
    good = {"days": {"mon": day(100, 80, 20, ot=(50, 45, 5), day_=60, night=40)}}
    t("맞으면 조용하다", OT.audit_division(good) == [])

    # 반올림 때문에 생기는 1명 차이는 검산에 안 걸린다 (요일 값이 맞으니까)
    rounder = {"days": {d: day(101, 81, 20, ot=(1, 1, 0), day_=61, night=40)
                        for d in ("mon", "tue", "wed")}}
    t("반올림 차이는 안 걸린다", OT.audit_division(rounder) == [])

    adm = OT.for_admin(OT.put_week({}, "2026-W39", {"divisions": {"x": bad}}))
    t("관리 화면이 검산을 같이 준다", adm["audit_count"] == 3)
    t("관리 화면이 집계도 같이 준다", adm["total"]["available"]["total"] == 100)
    t("관리 화면이 고칠 원본도 준다",
      adm["divisions"]["x"]["days"]["mon"]["overtime"]["people"]["total"] == 50)

    print("test_overtime: 전부 통과 (%d개)" % ok)


if __name__ == "__main__":
    main()
