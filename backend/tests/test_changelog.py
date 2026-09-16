# 버전마다 뭐가 바뀌었는지가 남는다
#   python3 backend/tests/test_changelog.py
#
# "새 버전 뜰 때 마다 뭐가 변경 되었는지를 작성해주면 좋겠는데
#  2.3.x기준으로 그냥 계속 쌓이고 있는것 같은 느낌이 들어"
#
# 쌓인 게 아니라 얼어 있었다. app_version.json 에 release_notes 가 한 줄
# 있고 배포할 때 그걸 그대로 썼다. 안 고치면 옛 노트가 나간다. 실제로
# 2.3.10 이 몇 버전 전의 블룸 일 보고 얘기를 띄우고 있었다.
import ast, pathlib, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]      # backend/
REPO = ROOT.parent
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
ok = 0

# ── CHANGELOG.md 가 있고 버전 항목이 있다 ──
CL = REPO / 'CHANGELOG.md'
assert CL.exists(), 'CHANGELOG.md 가 없다'
TXT = CL.read_text(encoding='utf-8')
assert '## 2.3.10' in TXT, '2.3.10 항목이 없다'
ok += 1

# ── 서버 파서 ──
g = {'BASE_DIR': ROOT}
for n in ast.parse(SRC).body:
    if isinstance(n, ast.Assign) and getattr(n.targets[0], 'id', '') in (
            '_CHANGELOG_FILE', '_CHANGELOG_FILE_ALT'):
        exec(ast.get_source_segment(SRC, n), g)
    if isinstance(n, ast.FunctionDef) and n.name in (
            '_parse_changelog', '_load_changelog', '_changelog_for'):
        exec(ast.get_source_segment(SRC, n), g)
for fn in ('_parse_changelog', '_load_changelog', '_changelog_for'):
    assert fn in g, f'{fn} 이 없다'

items = g['_load_changelog']()
assert items, '서버가 변경 내역을 못 읽는다'
assert len(items) >= 2, items

# 버전을 박아두면 배포할 때마다 이 테스트가 깨진다. 규칙만 지킨다.
import re as _re
_vers = [e['version'] for e in items if _re.fullmatch(r'\d+\.\d+\.\d+', e['version'])]
assert _vers, '버전 모양의 항목이 없다'


def _key(v):
    return tuple(int(x) for x in v.split('.'))


assert _vers == sorted(_vers, key=_key, reverse=True), f'최신이 위가 아니다: {_vers}'
assert all(e['body'].strip() for e in items), '본문이 빈 항목이 있다'
ok += 1

# ── 지금 배포된 버전은 반드시 적혀 있어야 한다 ──
#
# 이게 진짜 지켜야 할 규칙이다. 나가 있는 버전에 노트가 없으면
# 사용자는 '뭐가 바뀌었나' 에 답을 못 듣는다.
import json as _js
_av = _js.loads((ROOT / 'app_version.json').read_text(encoding='utf-8'))
_cur = str(_av.get('latest_version') or '')
assert g['_changelog_for'](_cur), f'배포된 {_cur} 의 변경 내역이 없다'
ok += 1

# 날짜 없는 머리('## 2.3.9 이전')도 머리로 잡혀야 한다.
# 안 그러면 앞 버전의 본문에 통째로 딸려 들어간다.
assert len(items) >= 2, '날짜 없는 항목이 앞 버전에 먹혔다'
assert '블룸' not in items[0]['body'], '2.3.10 본문에 옛 노트가 섞였다'
ok += 1

# ── 없는 버전은 빈 문자열 (release.sh 가 이걸로 배포를 막는다) ──
assert g['_changelog_for']('9.9.9') == ''
assert g['_changelog_for']('v2.3.10') == g['_changelog_for']('2.3.10') != ''
ok += 1

# ── release.sh 쪽 파서와 결과가 같아야 한다 ──
sys.path.insert(0, str(REPO))
import tools_changelog as _tc
for v in ('2.3.10', '2.3.9'):
    a = g['_changelog_for'](v).strip()
    b = _tc.notes_for(v, path=CL).strip()
    assert a == b, f'{v}: 서버와 release.sh 가 다른 노트를 본다'
assert _tc.notes_for('9.9.9', path=CL) == ''
ok += 1

# ── release.sh 가 항목 없으면 멈춘다 ──
SH = (REPO / 'release.sh').read_text(encoding='utf-8')
assert 'tools_changelog.py' in SH, 'release.sh 가 CHANGELOG 를 안 본다'
assert 'if [ -z "$NOTES" ]; then' in SH and 'CHANGELOG.md 에' in SH, \
    '노트가 없어도 배포가 그냥 나간다'
assert "json.load(open('backend/app_version.json'))['release_notes']" not in SH, \
    '아직 옛 노트 한 줄을 그대로 쓴다'
assert 'CHANGELOG.md' in SH.split('git add')[1][:120], 'CHANGELOG 를 커밋에 안 넣는다'
ok += 1

# ── /app/version 이 CHANGELOG 를 먼저 본다 ──
assert '_changelog_for(data.get("latest_version"))' in SRC, \
    '/app/version 이 아직 옛 노트만 본다'
assert '/app/changelog' in SRC, '변경 내역 API 가 없다'
ok += 1

# ── 도커 이미지에 들어가는지 (COPY backend/ . 만으로는 루트 파일이 안 간다) ──
DF = (ROOT / 'Dockerfile').read_text(encoding='utf-8')
assert 'COPY CHANGELOG.md' in DF, '이미지에 CHANGELOG 가 안 들어간다'
ok += 1

# ── 앱: 설정 → 변경 내역 ──
LIB = REPO / 'mobile' / 'lib'
CS = (LIB / 'screens' / 'changelog_screen.dart').read_text(encoding='utf-8')
assert '/app/changelog' in CS and 'ChangelogScreen' in CS
assert '설치됨' in CS, '지금 깔린 버전을 표시 안 한다'
ST = (LIB / 'screens' / 'settings_screen.dart').read_text(encoding='utf-8')
assert 'ChangelogScreen' in ST and '변경 내역' in ST, '설정에서 들어갈 데가 없다'
ok += 1

print(f'전부 통과 · {ok}개 항목')
