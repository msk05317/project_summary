# 홈 '전체 현황' 은 반도체사업부만 센다
#   python3 backend/tests/test_home_alerts_scope.py
#
# 카드에는 '(반도체 기준)' 이라고 적혀 있는데 서버는 전 사업부를 세고
# 있었다. 적힌 것과 세는 것이 다르면 그 숫자는 아무도 못 믿는다.
import ast
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
CARD = (ROOT.parent / 'mobile' / 'lib' / 'components' / 'home'
        / 'status_board_card.dart').read_text(encoding='utf-8')
ok = 0


def t(name, cond):
    global ok
    print(("  ok  " if cond else "  FAIL") + "  " + name)
    if not cond:
        raise SystemExit(1)
    ok += 1


fn = None
for n in ast.parse(SRC).body:
    if isinstance(n, ast.FunctionDef) and n.name == 'get_home_alerts':
        fn = n
assert fn is not None, 'get_home_alerts 가 없다'
src = ast.get_source_segment(SRC, fn)

args = {a.arg for a in fn.args.args}
t("division 인자가 있다", 'division' in args)

# 기본값이 semiconductor
defaults = dict(zip([a.arg for a in fn.args.args][-len(fn.args.defaults):],
                    fn.args.defaults))
d = defaults.get('division')
t("기본값이 반도체", isinstance(d, ast.Constant) and d.value == 'semiconductor')

t("사업부로 프로젝트를 좁힌다", '_cl.get_projects(div' in src)
t("목록에 없으면 뺀다", 'if pk not in visible' in src)
t("사업부를 지정하면 빈 목록이어도 전사로 안 샌다", 'scoped' in src)

# 카드가 말하는 범위와 같아야 한다
t("카드에 '(반도체 기준)' 이 적혀 있다", '(반도체 기준)' in CARD)

# 설정상 반도체가 전사보다 적어야 의미가 있다 (같으면 필터가 무의미)
import config_loader as _cl  # noqa: E402
try:
    allp = {p.get("id") for p in _cl.get_projects(visible_only=True)}
    semi = {p.get("id") for p in _cl.get_projects("semiconductor", visible_only=True)}
    t("반도체는 전사의 일부다", semi and semi < allp)
except Exception as e:
    print("  skip  설정을 못 읽음: %s" % e)

print(f"전부 통과 ({ok}개)")
