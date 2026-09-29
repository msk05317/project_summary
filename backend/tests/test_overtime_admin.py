# 잔·특근 관리 화면이 제대로 걸려 있는지
#   python3 backend/tests/test_overtime_admin.py
#
# 화면을 붙일 때 빼먹기 쉬운 자리가 넷이다 — 사이드바 항목, 페이지 이름,
# renderPage 분기, 그리고 '전사 화면' 취급(사업부 칸 흐리게 + 빵부스러기).
# 하나만 빠져도 메뉴를 눌렀을 때 '개발 중' 만 뜬다.
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
HTML = (ROOT / 'admin_v2.html').read_text(encoding='utf-8')
SRC = (ROOT / 'main.py').read_text(encoding='utf-8')
ok = 0


def t(name, cond):
    global ok
    print(("  ok  " if cond else "  FAIL") + "  " + name)
    if not cond:
        raise SystemExit(1)
    ok += 1


# ── 화면 ─────────────────────────────────────────────────────
t("사이드바에 잔·특근", 'data-page="overtime"' in HTML)
t("페이지 이름", "overtime: '잔·특근'" in HTML)
t("renderPage 분기", "window.renderOvertimePage();" in HTML)
t("window 에 매달려 있다", "window.renderOvertimePage=function" in HTML)

# 사업부 목록과 상관없는 전사 자료라, 사업부 칸이 걸려 있으면 안 된다
t("전사 화면으로 친다", "pg === 'overtime'" in HTML and "scope-all" in HTML)
t("빵부스러기가 '전사'", "_cb0" in HTML and "'전사'" in HTML)

# 사이드바는 '전사' 묶음 안 — 사업부 select 앞에 있어야 한다
i_ot = HTML.find('data-page="overtime"')
i_biz = HTML.find('id="v2-division-select"')
t("사업부 선택보다 위에 있다", 0 < i_ot < i_biz)

# 잠금이 기본. 잠금일 때 입력칸이 disabled 여야 한다
t("기본은 수정 잠금", "var _lock = true" in HTML)
t("잠금이면 입력칸이 닫힌다", "(_lock?' disabled':'')" in HTML)

# 비율·가중평균은 화면에서 만들지 않는다 — 두 군데 있으면 앱과 숫자가 갈린다.
# 화면은 서버가 준 total 을 그리고, 입력 중 보여 주는 즉석 비율만 직접 낸다.
t("집계는 서버가 준 값을 그린다", "_s.total" in HTML)
t("즉석 비율은 입력용이라고 적어 뒀다", "liveRate" in HTML and "저장하면" in HTML)

# ── 서버 ─────────────────────────────────────────────────────
t("관리 GET", '@app.get("/admin/overtime")' in SRC)
t("관리 PUT", '@app.put("/admin/overtime")' in SRC)
t("엑셀 올리기", '@app.post("/admin/overtime/import-xlsx")' in SRC)
t("앱 라우트", '@app.get("/overtime/week")' in SRC)

# 주차 저장은 통째 교체라, 줄어드는 저장을 막아야 한다
i_put = SRC.index('@app.put("/admin/overtime")')
put = SRC[i_put:i_put + 1800]
t("사업부가 줄면 409", "409" in put and "allow_delete" in put)
t("무엇이 지워지는지 말해 준다", "곳을 지웁니다" in put)

print("test_overtime_admin: 전부 통과 (%d개)" % ok)
