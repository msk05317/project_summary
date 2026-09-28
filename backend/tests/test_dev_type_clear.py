# 유형(dev_type)을 '—' 로 비우고 저장하면 지워져야 한다
#   python3 backend/tests/test_dev_type_clear.py
#
# 챔버에서 유형을 비우고 저장했더니 DEP챔버 가 되돌아왔다. 저장 쪽이
# 빈 값을 '안 보냈다' 로 보고 옛 값을 되살렸기 때문이다. 화면에서 비운 것과
# 아예 안 보낸 것은 다르다.
import ast, pathlib, re

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
ok = 0

# 저장 함수 본문을 떼어낸다
tree = ast.parse(SRC)
fn = None
for n in ast.walk(tree):
    if isinstance(n, ast.FunctionDef) and n.name == 'admin_put_project_models':
        fn = ast.get_source_segment(SRC, n)
assert fn, '모델 저장 함수를 못 찾았다'

# 옛 규칙(빈 값이면 옛 값)은 없어야 한다
assert 'str(m.get("dev_type") or old.get("dev_type") or "")' not in fn, \
    '빈 값을 보내도 옛 유형이 되살아난다'
assert '_sent_dt = "dev_type" in m' in fn, '키가 왔는지로 가르지 않는다'
ok += 1

# 규칙 자체를 돌려본다 (저장 함수에서 떼어 온 그대로)
def merge(sent: dict, old: dict) -> str:
    _sent_dt = "dev_type" in sent
    src = sent.get("dev_type") if _sent_dt else old.get("dev_type")
    return str(src or "").strip().upper()

# 화면에서 비우고 저장 → 지워진다
assert merge({'dev_type': ''}, {'dev_type': 'DEP챔버'}) == ''
ok += 1
# 값을 바꿔 보내면 그 값
assert merge({'dev_type': 'hvm'}, {'dev_type': 'DEP챔버'}) == 'HVM'
ok += 1
# 아예 안 보냈으면 옛 값을 지킨다 (엑셀 업로드 등 부분 저장)
assert merge({}, {'dev_type': 'DEP챔버'}) == 'DEP챔버'
ok += 1
# 둘 다 없으면 빈 값
assert merge({}, {}) == ''
ok += 1

# 양산 줄도 같은 규칙 (개발에서 넘어와도 비운 건 비운 것)
assert 'elif _sent_dt:' in fn and 'entry["dev_type"] = ""' in fn, \
    '양산 줄은 아직 비우기가 안 먹는다'
ok += 1

# admin 표는 항상 유형 칸을 보낸다 (안 보내면 서버가 옛 값을 지킨다)
HTML = (ROOT / 'admin_v2.html').read_text(encoding='utf-8')
assert re.search(r"const dt = r\.querySelector\('\[data-field=\"dev_type\"\]'\);\s*\n\s*if \(pn\) m\.part_number = pn\.value;\s*\n\s*if \(dt\) m\.dev_type = dt\.value;", HTML) \
    or 'if (dt) m.dev_type = dt.value;' in HTML, 'admin 표가 유형을 안 보낸다'
ok += 1

print(f'test_dev_type_clear: {ok} passed')
