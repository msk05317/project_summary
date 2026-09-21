# admin 에서 저장하면 새로고침 없이 바로 반영되는지.
#   python3 backend/tests/test_admin_refresh.py
#
# "저장을 눌러서 뭘 수정하거나 process 를 수정하면 바로바로 수정이 되는게
#  아니라 매번 새로고침해야지 반영이 되고 있어"
#
# 진행률 · 다음 단계 · 지연/보류 배지는 서버가 계산한다. 저장한 뒤 들고
# 있던 목록을 그대로 다시 그리기만 해서 옛 값이 남았다.
import pathlib

H = (pathlib.Path(__file__).resolve().parents[1] / 'admin_v2.html').read_text(encoding='utf-8')
ok = 0

# 1) 공용 갱신 함수
assert 'window.mdlRefresh = function(mode, modelId)' in H, '갱신 함수가 없다'
f = H[H.index('window.mdlRefresh = function(mode, modelId)'):]
f = f[:f.index('\n  };\n')]
assert "'/admin/projects/' + encodeURIComponent(pk) + '/models'" in f, '서버에서 다시 안 받는다'
assert "window._mdlAlerts = (d && d.alerts) || {}" in f, '지연 배지를 안 바꾼다'
assert "if (mode === 'all')" in f and "mode === 'one' && modelId" in f
# 저장 안 한 다른 줄의 입력은 살린다
assert "mode !== 'all' && onTable" in f and 'syncDomToData(box)' in f, \
    '한 모델만 바꿀 때 다른 줄의 입력이 날아간다'
# 그 사이 프로젝트를 바꿨으면 남의 목록을 덮지 않는다
assert 'pk !== _currentProjectKey' in f, '다른 프로젝트 목록으로 덮을 수 있다'
assert 'window.scrollTo(0, y)' in f, '다시 그리면 스크롤이 맨 위로 튄다'
ok += 1

# 2) 표 저장 뒤 — 통째로
sv = H[H.index('function saveModels(statusEl)'):]
sv = sv[:sv.index('\n  }\n')]
assert "window.mdlRefresh('all')" in sv, '표를 저장해도 옛 값이 남는다'
assert '재조회 X' not in sv, '재조회 안 하는 옛 길이 남아 있다'
ok += 1

# 3) Process 입력 → 목록으로 — 그 모델만
bk = H[H.index("document.getElementById('mdl-proc-back').addEventListener"):]
bk = bk[:bk.index('// 단계 상태 변경 핸들러')]
assert "window.mdlRefresh('one', d.model_id)" in bk, \
    'Process 를 고치고 목록으로 가도 진행률이 옛 값이다'
ok += 1

# 4) Process 입력을 열 때 표의 입력을 챙긴다 (다녀오면 살아 있게)
op = H[H.index('function openProcessEditor(modelId)'):]
op = op[:op.index('fetch(')]
assert 'syncDomToData(_tb)' in op, 'Process 입력을 다녀오면 표에서 고치던 값이 날아간다'
ok += 1

# 5) 현황 · 보류 저장 뒤 — 배지만
nt = H[H.index("noteSaveBtn.addEventListener('click'"):]
nt = nt[:nt.index('.catch(')]
assert "window.mdlRefresh('alerts')" in nt, '보류로 바꿔도 지연 배지가 남는다'
ok += 1

# 6) 날짜 칸 연도는 4자리까지
#    "년도 작성하는 칸에 6자 입력이 가능한데 년도면 최대 4자"
#    input[type=date] 는 max 가 없으면 연도를 275760년(6자리)까지 받는다.
import re as _re
for m in _re.finditer(r'<input type="date"[^>]*>', H):
    assert 'max="' in m.group(0), f'연도가 6자리까지 들어간다: {m.group(0)[:80]}'
for m in _re.finditer(r"(\w+)\.type = 'date';", H):
    tail = H[m.end():m.end() + 200]
    assert m.group(1) + '.max' in tail, '스크립트로 만든 날짜 칸에 max 가 없다'
ok += 1

print(f'전부 통과 · {ok}개 항목')
