# 모델 저장이 목록을 통째로 지우지 못하게 막는다
#   python3 backend/tests/test_model_delete_guard.py
#
# 모델 저장은 '전체 교체' 다. 화면이 목록을 덜 들고 저장하면 나머지가
# 통째로 지워진다. 실제로 챔버 19종·SpaceX 16종·자동차 9종이 그렇게
# 날아갔고, 서버 자동 백업은 10개뿐이라 거기까지 거슬러 가지도 못했다.
import ast
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
HTML = (ROOT / 'admin_v2.html').read_text(encoding='utf-8')
ok = 0


def t(name, cond):
    global ok
    print(("  ok  " if cond else "  FAIL") + "  " + name)
    if not cond:
        raise SystemExit(1)
    ok += 1


fn = None
for n in ast.parse(SRC).body:
    if isinstance(n, ast.FunctionDef) and n.name == 'admin_put_project_models':
        fn = ast.get_source_segment(SRC, n)
assert fn, 'admin_put_project_models 가 없다'

t("사라지는 모델을 센다", '_gone = [mid for mid in old_map' in fn)
t("allow_delete 가 없으면 막는다", 'payload.get("allow_delete")' in fn)
t("409 로 거부한다", '409' in fn)
t("무엇이 사라지는지 알려준다", '사라질 모델' in fn)
t("preview 는 막지 않는다", '_price_mode != "preview"' in fn)
t("저장 로그에 삭제 수를 남긴다", '삭제 {len(_gone)}종' in fn)

# 화면은 사람이 지웠을 때만 allow_delete 를 보낸다
t("지우기에서 표시", 'window._mdlDidDelete = true' in HTML)
t("저장에 실어 보낸다", 'allow_delete: !!window._mdlDidDelete' in HTML)
t("다시 불러오면 표시를 지운다", 'window._mdlDidDelete = false' in HTML)

# 되살리기
rest = None
for n in ast.parse(SRC).body:
    if isinstance(n, ast.FunctionDef) and n.name == 'admin_models_restore_missing':
        rest = ast.get_source_segment(SRC, n)
t("restore-missing 이 있다", rest is not None)
t("있는 모델은 안 건드린다", 'not in have' in rest)
t("preview 가 기본", '"preview"' in rest)
t("복구 파일 디렉터리", 'RESTORE_DIR' in SRC)
t("복구 파일이 들어 있다",
  (ROOT / 'restore' / 'models_20260915_missing.json').exists())

print(f"전부 통과 ({ok}개)")
