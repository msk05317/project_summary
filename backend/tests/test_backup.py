# backup.sh 가 쓰레기를 멀쩡한 백업으로 저장하지 않는지
#   python3 backend/tests/test_backup.py
#
# 지난번에 데이터가 통째로 날아간 적이 있어서, 백업 파일만은 확실해야 한다.
# 0 바이트·flyctl 에러 메시지·깨진 JSON·프로젝트 0개는 저장하면 안 된다.
import json, os, pathlib, re, subprocess, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
SH = (ROOT / 'backup.sh').read_text(encoding='utf-8')

m = re.search(r"python3 - \"\$OUT/models[^\n]*<<'PY'[^\n]*\n(.*?)\nPY\n", SH, re.S)
assert m, 'backup.sh 의 검증부를 못 찾았다'

f = tempfile.NamedTemporaryFile('w', suffix='.py', delete=False, encoding='utf-8')
f.write(m.group(1)); f.close()


def run(raw):
    src = tempfile.NamedTemporaryFile('w', suffix='.json', delete=False, encoding='utf-8')
    src.write(raw); src.close()
    dst = src.name + '.shape'
    r = subprocess.run(['python3', f.name, src.name, dst], capture_output=True, text=True)
    kept = os.path.exists(src.name)
    shape = pathlib.Path(dst).read_text(encoding='utf-8') if os.path.exists(dst) else ''
    for p in (src.name, dst):
        if os.path.exists(p):
            os.unlink(p)
    return r.returncode, r.stdout + r.stderr, kept, shape


GOOD = json.dumps({'projects': {
    'chamber': {'models': [{'weekly_plan': {'2026-08': {'W32': {}, 'W33': {}}},
                            'process': [{}], 'note': '메모'}]},
    'powerbox': {'models': [{}, {}]}}}, ensure_ascii=False)

ok = 0
cases = [
    ('정상 파일',        GOOD,                                         0, True),
    ('flyctl 안내문',    'Connecting to fdaa:a2:6ab2:a7b::2...\n' + GOOD, 0, True),
    ('빈 파일',          '',                                           1, False),
    ('프로젝트 0개',     '{"projects": {}}',                           1, False),
    ('flyctl 에러',      'Error: no such app "project-summary-mkoo"',   1, False),
    ('깨진 JSON',        '{"projects": {"chamber": ',                   1, False),
]
for name, raw, want_rc, want_kept in cases:
    rc, out, kept, _ = run(raw)
    assert rc == want_rc, f'{name}: 종료코드 {rc} (기대 {want_rc})\n{out}'
    assert kept == want_kept, f'{name}: 파일이 {"남았다" if kept else "지워졌다"}\n{out}'
    ok += 1

# 안내문이 섞여 있어도 파일에서 걷어내고 저장해야 한다
src = tempfile.NamedTemporaryFile('w', suffix='.json', delete=False, encoding='utf-8')
src.write('Connecting to fdaa::2...\n' + GOOD); src.close()
subprocess.run(['python3', f.name, src.name, src.name + '.shape'], capture_output=True)
saved = json.loads(pathlib.Path(src.name).read_text(encoding='utf-8'))
assert set(saved['projects']) == {'chamber', 'powerbox'}, saved
os.unlink(src.name); os.unlink(src.name + '.shape')
ok += 1

# shape 에 개수가 제대로 찍히는지
_, _, _, shape = run(GOOD)
assert 'chamber' in shape and '모델    1' in shape and '주차     2' in shape, shape
assert '모델    2' in shape, shape          # powerbox
ok += 1

# 한 단계가 실패해도 나머지를 계속해야 한다 (set -e 로 멈추면 안 된다)
assert not re.search(r'^set -e', SH, re.M), \
    'set -e 가 있으면 API 스냅샷 실패가 models.json 백업까지 막는다'
ok += 1
# 순서: models.json 원본이 먼저다
assert SH.index('models.json 원본 받는 중') < SH.index('공개 API 스냅샷 받는 중'), \
    '제일 중요한 백업을 먼저 받아야 한다'
ok += 1

os.unlink(f.name)
print(f'전부 통과 ({ok}/{len(cases) + 4})')
