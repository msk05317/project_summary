# -*- coding: utf-8 -*-
"""올리기 미리보기의 '못 읽은 줄' 을 끝까지 볼 수 있는가.

매입·잔특근 화면은 못 읽은 줄을 세 개만 보여주고 나머지를 '…' 로
감췄다. 파서가 직접 적어 둔 말이 "조용히 빠진 줄이 제일 위험하다" 인데,
화면이 스무 줄을 조용히 삼키고 있었다. 엑셀 모양이 바뀌어 한 블록이
통째로 안 읽혀도 세 줄만 보고 넣게 된다.

여기서 지키는 것
  · 두 화면이 같은 덩어리를 쓴다 (한 벌로 두지 않으면 한쪽만 고쳐진다)
  · 세 개로 자르고 버리는 자리가 남아 있지 않다
  · 전부 담되 접어 둔다 (늘 펼치면 화면이 길어진다)
  · 펼치는 버튼이 다시 그려져도 동작한다 (문서에서 받는다)
  · 파서는 여전히 못 읽은 줄을 warnings 로 올려 보낸다
"""
import re
import sys
from pathlib import Path

BACK = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACK))

FAIL = []


def ok(c, m):
    if not c:
        FAIL.append(m)


AV2 = (BACK / "admin_v2.html").read_text(encoding="utf-8")


# ── 1. 한 벌로 두었는가 ─────────────────────────────────────────────
ok("window._impWarnBlock = function" in AV2, "공용 덩어리가 없다")
ok(AV2.count("window._impWarnBlock(") == 2,
   "쓰는 자리가 %d곳이다 (매입·잔특근 두 곳이어야 한다)"
   % AV2.count("window._impWarnBlock("))


# ── 2. 세 개로 자르고 버리는 자리가 남았나 ──────────────────────────
#
# w.slice(0,3) 자체는 '앞 세 개를 먼저 보여준다' 라서 덩어리 **안에서는**
# 맞다. 밖에 남아 있으면 거기서 나머지를 버린다는 뜻이다.
_i = AV2.index("window._impWarnBlock = function")
_d, _j = 0, AV2.index("{", _i)
_k = _j
while True:
    c = AV2[_k]
    if c == "{":
        _d += 1
    elif c == "}":
        _d -= 1
        if _d == 0:
            break
    _k += 1
BLOCK, REST = AV2[_i:_k], AV2[:_i] + AV2[_k:]

ok("w.slice(0, 3)" in BLOCK or "w.slice(0,3)" in BLOCK,
   "덩어리가 앞 세 개를 먼저 보여주지 않는다")
_left = re.findall(r"warnings?\s*\|\|\s*\[\][^\n]*slice\(0\s*,\s*3\)", REST)
ok(not _left, "덩어리 밖에 아직 세 개로 자르는 자리가 있다: %r" % _left)
for frag in ("esc(w.slice(0,3).join(' / '))", "w.slice(0,3).join(' / ')"):
    ok(frag not in REST, "옛 코드가 남아 있다: %s" % frag)


# ── 3. 전부 담되 접어 두는가 ────────────────────────────────────────
ok("w.map(function(x, i)" in BLOCK, "못 읽은 줄을 전부 담지 않는다")
ok("hidden" in BLOCK, "펼치기 전에 접어 두지 않는다")
ok("imp-warn-more" in BLOCK, "펼치는 버튼이 없다")
ok("overflow:auto" in BLOCK and "max-height" in BLOCK,
   "줄이 많으면 화면을 통째로 밀어낸다 (스크롤이 없다)")
# 세 개 이하면 접을 것도 없다
ok("w.length <= 3" in BLOCK, "세 개 이하일 때도 버튼을 단다")


# ── 4. 다시 그려져도 눌리는가 ───────────────────────────────────────
#
# 미리보기는 통째로 다시 그려진다. 버튼에 직접 건 핸들러는 그때 날아간다.
ok("document.addEventListener('click'" in AV2 and ".imp-warn-more" in AV2,
   "펼치는 버튼을 문서에서 받지 않는다 — 다시 그리면 안 눌린다")
ok("closest" in AV2[AV2.index(".imp-warn-more"):AV2.index(".imp-warn-more") + 400]
   or "closest('.imp-warn-more')" in AV2,
   "버튼 안쪽을 눌렀을 때를 못 잡는다")


# ── 5. 파서는 여전히 올려 보내는가 ──────────────────────────────────
for mod in ("purchase_import.py", "overtime_import.py"):
    src = (BACK / mod).read_text(encoding="utf-8")
    ok("warnings" in src, "%s 가 못 읽은 줄을 안 올려 보낸다" % mod)

SRC = (BACK / "main.py").read_text(encoding="utf-8")
ok('"warnings": parsed["warnings"]' in SRC
   or '"warnings": parsed.get("warnings") or []' in SRC,
   "라우트가 못 읽은 줄을 화면에 안 내려 준다")
ok(SRC.count('"warnings"') >= 2, "두 라우트 중 한쪽만 내려 준다")


if FAIL:
    print("실패 %d건" % len(FAIL))
    for f in FAIL:
        print("  -", f)
    raise SystemExit(1)
print("전부 통과 · 검사 5묶음")
