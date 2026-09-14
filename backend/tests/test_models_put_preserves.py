# 모델 관리 저장이 다른 화면의 데이터를 되돌리지 않는지 검증
#   python3 backend/tests/test_models_put_preserves.py
#
# 목록 화면은 열 때 받아 둔 사본을 저장할 때 그대로 돌려보낸다.
# 그 사이에 다른 곳(주차 계획, 엑셀 업로드, Process 입력)에서 들어간 내용이
# 옛날 값으로 덮이면 안 된다.
import pathlib, re

SRC = (pathlib.Path(__file__).resolve().parents[1] / 'main.py').read_text(encoding='utf-8')
ok = 0

# 1. 승계 목록에서 서버 값을 먼저 본다
block = SRC[SRC.index('for _keep in ("weekly_plan"'):]
block = block[:block.index('# 파트넘버는')]
assert 'if old.get(_keep) is not None:' in block, block[:400]
assert block.index('old.get(_keep)') < block.index('m.get(_keep)'), '아직 보낸 값을 먼저 본다'
ok += 1

# 2. 주차 계획이 승계 목록에 있다 (파워박스 9월이 이렇게 사라졌다)
for k in ('weekly_plan', 'weekly_progress', 'weekly_summary', 'auto',
          'current_expected', 'current_stage'):
    assert f'"{k}"' in block, k
ok += 1

# 3. 파트넘버는 이 화면에서 고칠 수 있어야 한다
assert 'if m.get("part_number") is not None:' in SRC
ok += 1

# 4. 프로세스는 서버 것만 쓴다
assert '_proc = old.get("process")' in SRC
ok += 1

# 5. 저장 흐름을 흉내 내어 되돌아가지 않는지 본다
def keep(payload, stored):
    out = {}
    for k in ('weekly_plan', 'weekly_progress', 'weekly_summary', 'auto'):
        if stored.get(k) is not None:
            out[k] = stored[k]
        elif payload.get(k) is not None:
            out[k] = payload[k]
    return out

서버 = {'weekly_plan': {'2026-08': {'W32': {'plan': 30}}, '2026-09': {'W37': {'plan': 50}}}}
목록이_보낸_옛날값 = {'weekly_plan': {'2026-08': {'W32': {'plan': 30}}}}
got = keep(목록이_보낸_옛날값, 서버)
assert '2026-09' in got['weekly_plan'], got          # 9월이 살아남아야 한다
ok += 1

# 서버에 없고 보낸 값에만 있으면 그건 받는다 (새로 생긴 모델)
got2 = keep({'weekly_plan': {'2026-09': {}}}, {})
assert got2['weekly_plan'] == {'2026-09': {}}
ok += 1

# 6. 백업을 들여다보고 되돌릴 수단이 있다
assert '@app.get("/admin/models/backups")' in SRC
assert '@app.post("/admin/models/restore")' in SRC
assert 'projects 를 주면 그 프로젝트만' in SRC, '통째 복원만 되면 위험하다'
ok += 1

print(f'전부 통과 ({ok}/7)')
