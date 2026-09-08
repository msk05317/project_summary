"""보드 행 구성(config/boards.json) 회귀 테스트.

프로젝트가 늘 때마다 여기 스펙만 고치면 되게 만들어 뒀는데, 오타가 나면
그 행이 조용히 0 이 되거나 다른 행과 겹쳐 합계가 틀린다. 화면에서는
멀쩡해 보이므로 여기서 잡는다.

    cd backend && python3 tests/test_boards.py
"""
import json
import sys
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BASE))

SPEC = json.loads((BASE / "config" / "boards.json").read_text(encoding="utf-8"))
BOARDS = SPEC["boards"]

ROW_KEYS = {"key", "label", "models", "dev_type", "group",
            "exclude", "exclude_dev_type", "manual", "status", "note"}
BOARD_KEYS = {"columns", "month_span", "sections",
              "show_status", "show_note", "next_month"}


def _rows(board):
    for sec in board.get("sections", []):
        for r in sec.get("rows", []):
            yield sec, r


def test_known_projects():
    """지금까지 정의한 프로젝트가 그대로 있는지."""
    assert set(BOARDS) >= {"chamber", "enclosure", "powerbox"}, sorted(BOARDS)


def test_shape():
    """오타난 키가 섞이면 조용히 무시되므로 이름을 검사한다."""
    for pk, b in BOARDS.items():
        assert b.get("columns") in ("week", "month"), f"{pk}: columns={b.get('columns')}"
        assert b.get("sections"), f"{pk}: sections 없음"
        for k in b:
            assert k in BOARD_KEYS, f"{pk}: 모르는 키 '{k}'"
        for sec, r in _rows(b):
            assert r.get("key"), f"{pk}: key 없는 행 {r}"
            assert r.get("label"), f"{pk}/{r.get('key')}: label 없음"
            for k in r:
                assert k in ROW_KEYS, f"{pk}/{r['key']}: 모르는 키 '{k}'"


def test_keys_unique():
    """행 key 가 겹치면 직접 입력값이 서로 덮어쓴다."""
    for pk, b in BOARDS.items():
        keys = [r["key"] for _s, r in _rows(b)]
        dup = {k for k in keys if keys.count(k) > 1}
        assert not dup, f"{pk}: key 중복 {dup}"


def test_row_has_source():
    """행은 모델을 가리키거나(models/dev_type/group) 직접 입력이어야 한다."""
    for pk, b in BOARDS.items():
        for _s, r in _rows(b):
            has = any(r.get(k) for k in ("models", "dev_type", "group")) or r.get("manual")
            assert has, f"{pk}/{r['key']}: 가리키는 대상이 없다"


def test_no_double_count():
    """같은 품번이 두 행에 들어가면 합계가 두 번 세어진다."""
    for pk, b in BOARDS.items():
        seen = {}
        for _s, r in _rows(b):
            for mid in (r.get("models") or []):
                assert mid not in seen, \
                    f"{pk}: {mid} 이 '{seen.get(mid)}' 와 '{r['key']}' 두 행에 있다"
                seen[mid] = r["key"]


def test_powerbox_partition():
    """모델 한 벌을 만들어 네 줄에 정확히 한 번씩만 들어가는지 확인."""
    import re
    src = (BASE / "main.py").read_text(encoding="utf-8")
    ns = {}
    for fn in ("_as_int", "_norm_group", "_board_row_models"):
        m = re.search(r"^def %s\(.*?(?=^(?:def |@app|class ))" % fn, src, re.S | re.M)
        exec(m.group(0), ns)

    models = [{"id": "925-800083-394", "group": "양산", "dev_type": ""}]
    models += [{"id": f"m{i}", "group": "양산", "dev_type": ""} for i in range(18)]
    models += [{"id": f"d{i}", "group": "개발", "dev_type": "SABRE 3D"} for i in range(22)]
    models += [{"id": f"e{i}", "group": "양산", "dev_type": "EMA"} for i in range(10)]
    models += [{"id": f"x{i}", "group": "개발", "dev_type": "EMA"} for i in range(15)]
    proj = {"models": models}

    hits = {}
    for _s, r in _rows(BOARDS["powerbox"]):
        for m in ns["_board_row_models"](proj, r):
            hits.setdefault(m["id"], []).append(r["key"])

    dup = {k: v for k, v in hits.items() if len(v) > 1}
    assert not dup, f"두 행에 걸친 모델: {dup}"
    assert len(hits["925-800083-394"]) == 1 and hits["925-800083-394"] == ["aether"]
    counts = {}
    for ids in hits.values():
        counts[ids[0]] = counts.get(ids[0], 0) + 1
    assert counts.get("mass19") == 18, counts
    assert counts.get("dev22") == 22, counts
    assert counts.get("ema10") == 10, counts
    # 개발 EMA 15종은 어느 행에도 안 들어간다 (엑셀에 그 줄이 없다)
    assert len(hits) == 51, len(hits)


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
