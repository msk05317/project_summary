"""모델 엑셀 업로드가 무엇을 열쇠로 쓰는지 고정한다.

큐리 파일은 '버스바' 5줄, '시트메탈' 6줄이 파트넘버로만 갈린다.
모델명으로 맞추던 시절에는 16줄이 7종으로 뭉개져 들어갔고, 화면에서는
그냥 모델이 적어 보일 뿐이라 눈에 안 띄었다.

main.py 를 import 하면 FastAPI 가 뜨므로 머리글·열쇠 규칙만 그대로 옮겨 확인한다.
규칙이 바뀌면 여기서 먼저 걸린다.

    cd backend && python3 tests/test_models_import.py
"""
import re
import sys
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
SRC = (BASE / "main.py").read_text(encoding="utf-8")


def _header_map(headers):
    """main.py 의 머리글 인식 규칙."""
    col = {}
    for c, t in enumerate(headers, start=1):
        t = str(t or "").strip()
        k = t.replace(" ", "").replace(".", "").lower()
        if t in ("모델", "모델명"):
            col["name"] = c
        elif t == "구분":
            col["group"] = c
        elif t in ("유형", "개발 유형"):
            col["dev_type"] = c
        elif t.startswith("판가"):
            col["price"] = c
        elif t.startswith("재료비"):
            col["material_cost"] = c
        elif k in ("파트넘버", "파트번호", "품번", "partno", "partnumber"):
            col["part_number"] = c
        elif k.startswith("po"):
            col["po_qty"] = c
        elif k in ("실적수량", "출하수량", "출하실적", "실적", "출하"):
            col["shipped_qty"] = c
        elif t == "비고":
            col["note"] = c
    return col


def _import(headers, rows):
    """열쇠 규칙만 돌려 등록된 모델 목록을 만든다."""
    col = _header_map(headers)
    out, by_name, by_pn = [], {}, {}
    for row in rows:
        name = str(row[col["name"] - 1] or "").strip() if col.get("name") else ""
        pn = str(row[col["part_number"] - 1] or "").strip() if col.get("part_number") else ""
        if not name and not pn:
            continue
        name = name or pn
        cur = by_pn.get(pn.lower()) if pn else by_name.get(name.lower())
        if cur is None:
            cur = {"id": pn or name, "name": name, "part_number": pn}
            out.append(cur)
            by_name.setdefault(name.lower(), cur)
            if pn:
                by_pn[pn.lower()] = cur
        if col.get("po_qty"):
            cur["po_qty"] = row[col["po_qty"] - 1]
    return out


CURIE_HEAD = ["파트넘버", "모델명", "구분", "유형", "판가", "재료비", "PO수량", "실적수량", "비고"]
CURIE_ROWS = [
    ["568D", "버스바", None, None, 50, 12.7, 880, 0, None],
    ["569D", "버스바", None, None, 49, 12.7, 440, 0, None],
    ["566D", "버스바", None, None, 430, 202.7, 20, 0, None],
    ["562D", "시트메탈", None, None, 12, 3.9, 200, 0, None],
    ["561D", "시트메탈", None, None, 8, 0.7, 40, 0, None],
]


def test_머리글을_알아본다():
    col = _header_map(CURIE_HEAD)
    for k in ("part_number", "name", "group", "dev_type", "price",
              "material_cost", "po_qty", "shipped_qty", "note"):
        assert k in col, f"{k} 열을 못 찾았습니다: {col}"


def test_이름이_같아도_파트넘버로_갈린다():
    """큐리: 버스바 3줄 + 시트메탈 2줄 → 5종이어야 한다."""
    got = _import(CURIE_HEAD, CURIE_ROWS)
    assert len(got) == 5, [m["id"] for m in got]
    assert [m["id"] for m in got] == ["568D", "569D", "566D", "562D", "561D"]
    assert [m["po_qty"] for m in got] == [880, 440, 20, 200, 40]


def test_같은_파트넘버는_한_줄로_합쳐진다():
    rows = CURIE_ROWS + [["568D", "버스바", None, None, 55, 13, 900, 0, None]]
    got = _import(CURIE_HEAD, rows)
    assert len(got) == 5, [m["id"] for m in got]
    assert got[0]["po_qty"] == 900, got[0]


def test_파트넘버_열이_없으면_예전처럼_모델명으로():
    head = ["모델명", "구분", "판가", "재료비"]
    rows = [["키스톤", "양산", 4950, 0], ["키스톤", "양산", 5000, 0]]
    got = _import(head, rows)
    assert len(got) == 1, got


def test_main_에_규칙이_실제로_들어있다():
    """테스트만 통과하고 본체가 옛날이면 의미가 없다."""
    assert 'col_map["part_number"] = c' in SRC, "파트넘버 열 인식이 main.py 에 없습니다"
    assert "by_pn.get(pn.lower())" in SRC, "파트넘버 우선 매칭이 main.py 에 없습니다"
    assert re.search(r'col_map\.get\("po_qty"\)', SRC), "PO수량 반영이 main.py 에 없습니다"


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
