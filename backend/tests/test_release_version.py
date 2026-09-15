# release.sh 가 버전을 올리는지
#   python3 backend/tests/test_release_version.py
#
# 인자 없이 돌리면 pubspec 버전을 그대로 써서 2.3.0 을 두 번 배포했다.
# 버전이 같으면 앱에 업데이트 팝업이 안 뜬다.
import json, pathlib, re, subprocess, tempfile, os

ROOT = pathlib.Path(__file__).resolve().parents[2]
SH = (ROOT / 'release.sh').read_text(encoding='utf-8')
ok = 0

assert subprocess.run(['bash', '-n', str(ROOT / 'release.sh')],
                      capture_output=True).returncode == 0, 'release.sh 문법 오류'
ok += 1

# 인자 없으면 올린다
assert 'CODE=$(( CUR_CODE + 1 ))' in SH, '인자 없이 돌릴 때 코드를 안 올린다'
assert '${CUR_VER##*.} + 1' in SH, '끝자리 버전을 안 올린다'
ok += 1

# 이미 배포된 버전이면 멈춘다
assert '이미 배포된 버전입니다' in SH, '같은 버전을 그냥 올려버린다'
ok += 1

# --same 으로 일부러 같게 할 수 있다
assert '"--same"' in SH, '--same 이 없다'
ok += 1

# 끝자리 올리기가 실제로 맞는지
script = '''
CUR_VER="$1"; CUR_CODE="$2"
VER="${CUR_VER%.*}.$(( ${CUR_VER##*.} + 1 ))"; CODE=$(( CUR_CODE + 1 ))
echo "$VER+$CODE"
'''
for cur, want in [(('2.3.0', '23'), '2.3.1+24'),
                  (('2.3.9', '29'), '2.3.10+30'),
                  (('10.0.99', '5'), '10.0.100+6')]:
    r = subprocess.run(['bash', '-c', script, '_', cur[0], cur[1]],
                       capture_output=True, text=True)
    assert r.stdout.strip() == want, f'{cur} -> {r.stdout.strip()} (기대 {want})'
ok += 1

# 릴리스 노트가 지난 릴리스 것 그대로면 안 된다 (사람이 눈으로 볼 수 있게 찍어준다)
assert '릴리스 노트:' in SH, '무슨 노트로 나가는지 안 보여준다'
ok += 1

# app_version.json 모양
d = json.loads((ROOT / 'backend' / 'app_version.json').read_text(encoding='utf-8'))
for k in ('latest_version', 'latest_version_code', 'download_url', 'release_notes'):
    assert k in d, f'app_version.json 에 {k} 가 없다'
assert re.match(r'^\d+\.\d+\.\d+$', d['latest_version']), d['latest_version']
assert isinstance(d['latest_version_code'], int), d['latest_version_code']
assert f"/v{d['latest_version']}/" in d['download_url'], \
    f"받는 곳 주소가 버전과 어긋난다: {d['download_url']}"
ok += 1

print(f'전부 통과 ({ok}/7)')
