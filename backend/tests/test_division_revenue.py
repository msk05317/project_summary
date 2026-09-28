# 매출 관리는 고른 사업부의 숫자를 보여준다
#   python3 backend/tests/test_division_revenue.py
#
# revenue.json 은 반도체 주간보고 한 장이 원본인데, 매출 관리가 사이드바
# '사업부' 그룹에 있어서 PCB 를 골라도 반도체 숫자가 떴다. 사업부를 고른
# 사람에게 다른 사업부 숫자를 보여주면 안 된다.
import ast
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
HTML = (ROOT / 'admin_v2.html').read_text(encoding='utf-8')
tree = ast.parse(SRC)
ok = 0


def t(name, cond):
    global ok
    print(("  ok  " if cond else "  FAIL") + "  " + name)
    if not cond:
        raise SystemExit(1)
    ok += 1


# ── 서버 ─────────────────────────────────────────────────────
fns = {n.name for n in tree.body if isinstance(n, ast.FunctionDef)}
t("_div_revenue_view 가 있다", "_div_revenue_view" in fns)
t("/admin/division/revenue 라우트", '@app.get("/admin/division/revenue")' in SRC)

src = next(ast.get_source_segment(SRC, n) for n in tree.body
           if isinstance(n, ast.FunctionDef) and n.name == "_div_revenue_view")
t("홈 카드와 같은 자리에서 온다", "_home_division_rows" in src)
t("출처를 같이 준다", '"actual_source"' in src and '"target_source"' in src)
t("없는 사업부는 404", "404" in src)
t("프로젝트별로 쪼갠다", "_div_model_money" in src)

# ── 화면 ─────────────────────────────────────────────────────
t("반도체가 아니면 사업부 매출을 부른다",
  "/admin/division/revenue?div=" in HTML)
t("반도체는 예전 화면 그대로",
  "_dv !== 'semiconductor'" in HTML and "/admin/revenue/state?month=" in HTML)
t("사업부 화면 그리기", "function dvView(" in HTML and "function dvWire(" in HTML)
t("어느 사업부 숫자인지 말해 준다", "의 숫자입니다" in HTML)
t("타겟은 홈 관리와 같은 곳에 저장", "/admin/home/division-target" in HTML)

# 분기가 fetch 보다 먼저 와야 한다 — 뒤에 있으면 반도체 값을 한 번 받는다
i_branch = HTML.find("_dv !== 'semiconductor'")
i_state = HTML.find("/admin/revenue/state?month=", i_branch)
t("분기가 먼저", 0 < i_branch < i_state)

print(f"전부 통과 ({ok}개)")
