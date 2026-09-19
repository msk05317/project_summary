# 보드 행 입력창이 '지금 보는 프로젝트' 의 행 구성만 쓰는지.
#   python3 backend/tests/test_board_row_editor.py
#
# 챔버(섹션형)를 보고 나서 하바플레이트로 넘어가면, 전역 _wbSpecData 에
# 챔버의 행 구성(기존 / 내재화 / Dep 챔버)이 그대로 남아 있었다.
# 그 상태로 'PO · 실적 · 증감 입력' 을 누르면 챔버 행이 뜨고, 저장하면
# 챔버의 행 키가 하바플레이트에 적힌다 — 화면만 이상한 게 아니라 데이터가 섞인다.
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
H = (ROOT / 'backend' / 'admin_v2.html').read_text(encoding='utf-8')
ok = 0

# 1) 섹션형을 그릴 때 어느 프로젝트 것인지 같이 적어둔다
i = H.index('function _wbRenderSections(box, pk, d)')
head = H[i:i + 300]
assert 'window._wbSpecData = d;' in head, '섹션형 spec 을 안 적는다'
assert 'window._wbSpecPk = pk;' in head, '어느 프로젝트 spec 인지 안 적는다'
ok += 1

# 2) 보드를 새로 그릴 때마다 지운다 — 섹션형이 아니면 남아 있으면 안 된다
j = H.index("if (d.layout === 'sections') { _wbRenderSections(box, pk, d); return; }")
before = H[max(0, j - 500):j]
assert 'window._wbSpecData = null;' in before, '이전 프로젝트 행 구성을 안 지운다'
assert 'window._wbSpecPk = pk;' in before, '새 프로젝트 키를 안 적는다'
ok += 1

# 3) 버튼은 같은 프로젝트일 때만 섹션형 입력창을 연다
k = H.index('wbBtn.onclick = function()')
btn = H[k:k + 900]
assert "_spec.layout === 'sections'" in btn and 'window._wbSpecPk === _pk' in btn, \
    '프로젝트 확인 없이 섹션형 입력창을 연다'
assert 'window.openBoardEditor();' in btn, '일반 프로젝트가 갈 곳이 없다'
ok += 1

# 4) 입력창 자체에도 빗장 (버튼 말고 다른 데서 불러도 막힌다)
m = H.index('function _wbOpenRowEditor(pk)')
ed = H[m:m + 600]
assert "d.layout !== 'sections'" in ed and 'window._wbSpecPk !== pk' in ed, \
    '입력창이 남의 행 구성을 그대로 쓴다'
assert 'return;' in ed, '막고 나서 그냥 진행한다'
ok += 1

# 5) 저장은 인자로 받은 pk 로만 간다 (전역 프로젝트 키를 다시 읽지 않는다)
save = H[m:H.index('보드 행 입력', m) + 8000]
assert "'/admin/projects/' + encodeURIComponent(pk) + '/board-rows'" in save, \
    '저장 주소가 인자 pk 가 아니다'
ok += 1

print(f'전부 통과 · {ok}개 항목')
