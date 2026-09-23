# 사장님 지시사항 — 줄마다 기한 · 반복 · 완료
#   python3 backend/tests/test_home_orders.py
#
# 카드 하나에 등록일 하나만 붙이면 '9/30까지' 와 '매일 점검' 이 같아 보인다.
# 줄마다 따로 가지고, 급한 것부터 앱에 내려간다.
import pathlib, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import home_orders as ho          # noqa: E402

TODAY = '2026-09-23'
ok = 0

ITEMS = [
    {'text': '9월 마감까지 반도체 출하 목표 재점검', 'due_kind': 'date', 'due': '2026-09-30',
     'created': '2026-09-18'},
    {'text': '하바플레이트 지연 사유 매일 점검', 'due_kind': 'daily', 'created': '2026-09-20'},
    {'text': '재료비율 90% 넘는 품목 판가 재협의', 'due_kind': 'none', 'created': '2026-09-22'},
    {'text': '8월 미출하분 고객 회신 정리', 'due_kind': 'date', 'due': '2026-09-12',
     'created': '2026-09-05'},
    {'text': '끝난 지시', 'due_kind': 'none', 'created': '2026-09-01', 'done': True},
]

# ── 정렬: 지남 → 임박 → 반복 → 기한 없음 ──
live = ho.for_app(ITEMS, TODAY)
assert [i['text'][:3] for i in live] == ['8월 ', '9월 ', '하바플', '재료비'], \
    [i['text'][:3] for i in live]
assert all(not i['done'] for i in live) and len(live) == 4, '완료한 줄이 앱에 남았다'
ok += 1

# ── 꼬리표 ──
assert live[0]['badge'] == '지남 · D+11' and live[0]['tone'] == 'late', live[0]
assert live[1]['badge'] == 'D-7 · 9/30' and live[1]['tone'] == 'warn', live[1]
assert live[2]['badge'] == '매일' and live[2]['tone'] == 'repeat'
assert live[3]['badge'] == '9/22 등록' and live[3]['tone'] == 'plain'
ok += 1

# 3일 이내는 빨강, 오늘도 빨강
soon = ho.for_app([{'text': 'x', 'due_kind': 'date', 'due': '2026-09-25'}], TODAY)[0]
assert soon['tone'] == 'late' and soon['badge'] == 'D-2 · 9/25', soon
todo = ho.for_app([{'text': 'x', 'due_kind': 'date', 'due': TODAY}], TODAY)[0]
assert todo['badge'].startswith('오늘') and todo['tone'] == 'late', todo
ok += 1

# ── 저장 모양 ──
n = ho.normalize([{'text': '  빈 앞뒤  ', 'due_kind': '몰라'},
                  {'text': ''},                      # 빈 줄은 버린다
                  {'text': '날짜 없이 날짜까지', 'due_kind': 'date'}], TODAY)
assert len(n) == 2, n
assert n[0]['text'] == '빈 앞뒤' and n[0]['due_kind'] == 'none'
assert n[0]['created'] == TODAY, '등록일이 오늘로 안 박혔다'
assert n[1]['due_kind'] == 'none' and n[1]['due'] == '', '날짜 없는 날짜까지가 지남으로 뜬다'
assert all(i['id'] for i in n), 'id 가 없다'
ok += 1

# ── 완료 ──
done = ho.normalize([{'text': 'x', 'done': True}], TODAY)[0]
assert done['done'] and done['done_at'] == TODAY
back = ho.normalize([{**done, 'done': False}], TODAY)[0]
assert not back['done'] and back['done_at'] == '', '되돌렸는데 완료일이 남았다'
ok += 1

# ── 파일 저장/읽기 ──
with tempfile.TemporaryDirectory() as d:
    p = pathlib.Path(d) / 'home_orders.json'
    saved = ho.save(p, ITEMS, TODAY)
    assert len(saved['items']) == 5 and saved['updated_at']
    again = ho.load(p)
    assert [i['id'] for i in again['items']] == [i['id'] for i in saved['items']]
    assert ho.load(pathlib.Path(d) / '없는파일.json')['items'] == []
ok += 1

# ── 줄 수 제한 ──
assert len(ho.normalize([{'text': f'{i}'} for i in range(200)], TODAY)) == ho.MAX_ITEMS
ok += 1

# ── 엔드포인트가 붙어 있는지 ──
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
for route in ('@app.get("/home/orders")', '@app.get("/admin/home/orders")',
              '@app.put("/admin/home/orders")'):
    assert route in SRC, f'{route} 가 없다'
assert 'ORDERS_FILE = DATA_DIR / "home_orders.json"' in SRC
ok += 1

print(f'test_home_orders: {ok} passed')
