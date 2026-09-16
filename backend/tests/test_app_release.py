# 앱 배포 엔드포인트 — 버전 파일 우선순위와 받는 곳 바꿔치기 검증
#   python3 backend/tests/test_app_release.py
#
# 볼륨을 무조건 앞세우던 때가 있었다. 볼륨에 한참 전에 admin 으로 올린
# 2.1.9 가 남아 있어서, release.sh 로 2.3.8 을 배포해도 서버는 계속
# 2.1.9 를 알려줬다. 그 주소는 비공개 저장소 릴리스라 앱이 받지도 못해
# '업데이트 실패 404' 만 떴다. 이제 버전 코드가 높은 쪽이 이긴다.
import ast, json, pathlib, sys, tempfile

SRC = pathlib.Path(__file__).resolve().parents[1] / 'main.py'
src = SRC.read_text(encoding='utf-8')
tree = ast.parse(src)

want = {'_read_app_version', 'get_app_version', '_as_int',
        '_parse_changelog', '_load_changelog', '_changelog_for'}
grab = {}
for n in ast.walk(tree):
    if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name in want:
        n.decorator_list = []
        grab[n.name] = ast.unparse(n)
assert want <= set(grab), set(grab)

tmp = pathlib.Path(tempfile.mkdtemp())
VOL, SEED, APK = tmp / 'vol.json', tmp / 'seed.json', tmp / 'app.apk'

g = {'json': json, 'print': lambda *a, **k: None}
exec('\n\n'.join(grab.values()), g)
g.update({
    'APP_VERSION_FILE': VOL, 'APP_VERSION_SEED': SEED, 'APP_APK_FILE': APK,
    'BASE_DIR': tmp,
    # 변경 내역은 이 테스트가 보는 곳에 없다 — 없으면 옛 노트를 그대로 둔다
    '_CHANGELOG_FILE': tmp / 'CHANGELOG.md',
    '_CHANGELOG_FILE_ALT': tmp / 'CHANGELOG.md',
    'APP_VERSION_FALLBACK': {'latest_version': '1.0.0', 'latest_version_code': 1,
                             'download_url': '/app/download', 'release_notes': '',
                             'force_update': False},
})
read, ver = g['_read_app_version'], g['get_app_version']
w = lambda p, d: p.write_text(json.dumps(d, ensure_ascii=False), encoding='utf-8')
ok = 0

# 1. 아무것도 없으면 기본값
assert read()['latest_version'] == '1.0.0'; ok += 1

# 2. 이미지 파일(seed)만 있으면 그걸 쓴다
w(SEED, {'latest_version': '2.3.0', 'latest_version_code': 23,
         'download_url': 'https://github.com/x/y/releases/download/v2.3.0/a.apk'})
assert read()['latest_version_code'] == 23; ok += 1

# 3. 볼륨이 더 높으면 볼륨이 이긴다 (배포 없이 admin 으로 올릴 수 있어야 한다)
w(VOL, {'latest_version': '2.4.0', 'latest_version_code': 24})
assert read()['latest_version'] == '2.4.0'; ok += 1

# 3-1. 볼륨이 더 낮으면 이미지가 이긴다 — 옛 볼륨 파일이 배포를 막으면 안 된다
w(VOL, {'latest_version': '2.1.9', 'latest_version_code': 21})
assert read()['latest_version'] == '2.3.0', read()
ok += 1

# 4. 볼륨 파일이 깨져 있으면 seed 로 내려간다
VOL.write_text('{ 이건 json 이 아니다', encoding='utf-8')
assert read()['latest_version_code'] == 23; ok += 1
VOL.unlink()

# 5. APK 가 없으면 받는 곳을 건드리지 않는다. 대신 못 받는다고 알려 준다.
d0 = ver()
assert d0['download_url'].startswith('https://github.com')
assert d0['apk_ready'] is False, '받을 APK 가 없는데 있다고 한다'
ok += 1

# 6. APK 가 서버에 있으면 받는 곳을 서버로 돌린다
#    (비공개 저장소의 릴리스 주소는 앱이 못 받는다)
APK.write_bytes(b'PK\x03\x04not-a-real-apk')
d = ver()
assert d['download_url'] == '/app/download' and d['apk_url'] == '/app/download'
assert d['apk_ready'] is True
ok += 1

# 7. 원본은 건드리지 않는다 (seed 파일이 덮어써지면 안 된다)
assert json.loads(SEED.read_text(encoding='utf-8'))['download_url'].startswith('https://'); ok += 1

# 8. 앱은 받을 수 없는 주소면 팝업을 띄우지 않는다
U = (SRC.parents[1] / 'mobile' / 'lib' / 'services' / 'app_updater.dart').read_text(encoding='utf-8')
assert 'bool get downloadable' in U and "contains('github.com')" in U
assert 'if (!latest.downloadable)' in U, '못 받는데도 팝업을 띄운다'
assert '업데이트 실패: $e' not in U, 'Dio 예외를 그대로 보여준다'
assert '업데이트 파일이 서버에 없습니다' in U
ok += 1

# 9. release.sh 는 GitHub 이 아니라 우리 서버로 올린다
R = (SRC.parents[1] / 'release.sh').read_text(encoding='utf-8')
assert '/admin/app/release' in R and '/app/download' in R, 'release.sh 가 서버로 안 올린다'
assert 'gh release upload' not in R, 'GitHub 릴리스 업로드가 남아 있다'
assert 'app/download' in R and 'HTTP $DL' in R, '올린 뒤 받아지는지 확인하지 않는다'
ok += 1

print(f'전부 통과 ({ok}/7)')
