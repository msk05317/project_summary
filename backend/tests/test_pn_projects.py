# 파트넘버를 쓰는 프로젝트 목록이 한 곳에만 있는지
#   python3 backend/tests/test_pn_projects.py
#
# 예전에는 같은 목록이 세 군데 박혀 있었다 (머리글·입력칸·모델 추가).
# 큐리를 넣으면서 하나를 빼먹기 딱 좋은 모양이었다.
import pathlib, re

ROOT = pathlib.Path(__file__).resolve().parents[1]
HTML = (ROOT / 'admin_v2.html').read_text(encoding='utf-8')
ok = 0

m = re.search(r"window\.PN_PROJECTS = \[([^\]]*)\]", HTML)
assert m, 'PN_PROJECTS 를 못 찾았다'
keys = [k.strip().strip("'\"") for k in m.group(1).split(',') if k.strip()]
assert keys == ['powerbox', 'major_module', 'frame', 'spacex'], keys
ok += 1

# 목록이 다른 데 또 박혀 있으면 안 된다 (PN_PROJECTS 선언 한 줄만 허용)
stray = [ln for ln in HTML.split('\n')
         if re.search(r"\['powerbox'\s*,\s*'major_module'", ln)
         and 'PN_PROJECTS' not in ln]
assert not stray, f'같은 목록이 {len(stray)}군데 더 박혀 있다: {stray[:2]}'
assert "_pk === 'powerbox'" not in HTML, '모델 추가 쪽이 아직 직접 비교한다'
ok += 1

# 세 군데가 다 헬퍼를 쓴다
assert HTML.count('window._mdlHasPN(') >= 3, \
    f"_mdlHasPN 을 {HTML.count('window._mdlHasPN(')}군데서만 쓴다 (머리글·입력칸·모델 추가)"
ok += 1

# 큐리 키가 설정의 실제 키와 같은지
import json
cfg = json.loads((ROOT / 'config' / 'projects.json').read_text(encoding='utf-8'))
ids = {p.get('id') for p in (cfg.get('projects') if isinstance(cfg, dict) else cfg)}
missing = [k for k in keys if k not in ids]
assert not missing, f'설정에 없는 프로젝트 키: {missing}'
ok += 1

# 앱도 큐리를 반도체로 본다 (주차별 계획 표가 나와야 한다)
DART = (ROOT.parent / 'mobile' / 'lib' / 'screens' / 'model_list_screen.dart').read_text(encoding='utf-8')
assert "'frame', 'spacex'" in DART, '앱의 반도체 프로젝트 목록에 큐리가 없다'
ok += 1

print(f'전부 통과 ({ok}/5)')
