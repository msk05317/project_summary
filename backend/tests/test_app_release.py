# 앱 배포 엔드포인트 — 버전 파일 우선순위와 받는 곳 바꿔치기 검증
#   python3 backend/tests/test_app_release.py
import ast, json, pathlib, sys, tempfile

SRC = pathlib.Path(__file__).resolve().parents[1] / 'main.py'
src = SRC.read_text(encoding='utf-8')
tree = ast.parse(src)

want = {'_read_app_version', 'get_app_version', '_as_int'}
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

# 3. 볼륨 파일이 있으면 볼륨이 이긴다 (배포 없이 바꿀 수 있어야 한다)
w(VOL, {'latest_version': '2.4.0', 'latest_version_code': 24})
assert read()['latest_version'] == '2.4.0'; ok += 1

# 4. 볼륨 파일이 깨져 있으면 seed 로 내려간다
VOL.write_text('{ 이건 json 이 아니다', encoding='utf-8')
assert read()['latest_version_code'] == 23; ok += 1
VOL.unlink()

# 5. APK 가 없으면 받는 곳을 건드리지 않는다
assert ver()['download_url'].startswith('https://github.com'); ok += 1

# 6. APK 가 서버에 있으면 받는 곳을 서버로 돌린다
#    (비공개 저장소의 릴리스 주소는 앱이 못 받는다)
APK.write_bytes(b'PK\x03\x04not-a-real-apk')
d = ver()
assert d['download_url'] == '/app/download' and d['apk_url'] == '/app/download'; ok += 1

# 7. 원본은 건드리지 않는다 (seed 파일이 덮어써지면 안 된다)
assert json.loads(SEED.read_text(encoding='utf-8'))['download_url'].startswith('https://'); ok += 1

print(f'전부 통과 ({ok}/7)')
