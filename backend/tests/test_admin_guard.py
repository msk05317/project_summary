# -*- coding: utf-8 -*-
"""/admin 으로 시작하는 '쓰는' 주소에는 관리자 확인이 걸려 있어야 한다.

앱이 쓰는 주소는 일부러 열어 두었다 — 읽기만 하고, 사내에서만 쓰기 때문이다.
하지만 /admin 아래의 POST·PUT·PATCH·DELETE 는 자료를 바꾼다. 하나라도 열려
있으면 주소만 알면 누구나 고칠 수 있다.

실제로 PUT /admin/projects/{키}/types 하나가 빠져 있었다. 유형은 보드에서
줄을 묶는 기준이라, 통째로 갈아끼우면 그 유형으로 묶이던 줄이 사라진다.
바로 위의 GET 에는 걸려 있는데 PUT 만 빠진, 눈으로는 안 보이는 구멍이었다.

읽기(GET)는 여기서 막지 않는다. 지금 몇 개가 열려 있는데, 막으면 화면이
깨질 수 있어 따로 판단할 일이다. 대신 몇 개인지 세어서 늘어나면 알려 준다.
"""
import ast
import sys
from pathlib import Path

BACK = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACK))

FAIL = []


def ok(c, m):
    if not c:
        FAIL.append(m)


SRC = (BACK / "main.py").read_text(encoding="utf-8")
tree = ast.parse(SRC)

routes = []
for node in ast.walk(tree):
    if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
        continue
    for dec in node.decorator_list:
        if not (isinstance(dec, ast.Call) and isinstance(dec.func, ast.Attribute)):
            continue
        if not (isinstance(dec.func.value, ast.Name) and dec.func.value.id == "app"):
            continue
        m = dec.func.attr.lower()
        if m not in ("get", "post", "put", "delete", "patch"):
            continue
        if not dec.args or not isinstance(dec.args[0], ast.Constant):
            continue
        seg = ast.get_source_segment(SRC, node) or ""
        head = seg[:seg.index("):")] if "):" in seg else seg
        routes.append({
            "method": m.upper(),
            "path": dec.args[0].value,
            "func": node.name,
            "guarded": "get_admin_session" in head,
            "self_check": ("UPLOAD_PASSWORD" in seg or "_verify_session" in seg),
        })

ok(len(routes) > 150, "라우트를 제대로 못 읽었다: %d개" % len(routes))


# ── 1. /admin 아래의 쓰는 주소는 전부 막혀 있어야 한다 ──────────────
#
# 로그아웃만 예외다. 쿠키를 지우는 일뿐이라, 인증을 걸면 이미 만료된
# 사람이 로그아웃도 못 한다.
WRITE = ("POST", "PUT", "PATCH", "DELETE")
ALLOW = {"/admin/logout"}

holes = [r for r in routes
         if r["path"].startswith("/admin")
         and r["method"] in WRITE
         and not r["guarded"]
         and not r["self_check"]
         and r["path"] not in ALLOW]
ok(not holes,
   "관리자 확인 없이 자료를 바꾸는 주소가 있다:\n" +
   "\n".join("    %-6s %s  (%s)" % (h["method"], h["path"], h["func"]) for h in holes))


# ── 2. 그때 뚫려 있던 그 자리 ───────────────────────────────────────
types_put = [r for r in routes
             if r["method"] == "PUT" and r["path"].endswith("/types")
             and r["path"].startswith("/admin")]
ok(len(types_put) == 1, "유형 저장 주소를 못 찾았다")
if types_put:
    ok(types_put[0]["guarded"],
       "PUT /admin/projects/{키}/types 에 관리자 확인이 없다 — "
       "유형이 지워지면 보드에서 그 줄이 사라진다")


# ── 3. 읽기만 하는 /admin 주소 — 세어만 둔다 ────────────────────────
#
# 막으면 화면이 깨질 수 있어 여기서 강제하지 않는다. 다만 지금보다 늘어나면
# 누군가 새로 뚫어 둔 것이니 알려 준다.
open_gets = sorted(r["path"] for r in routes
                   if r["path"].startswith("/admin")
                   and r["method"] == "GET"
                   and not r["guarded"] and not r["self_check"])
KNOWN = [
    "/admin/config/projects",      # 화면 드롭다운
    "/admin/overview",             # 홈 대시보드 요약
    "/admin/projects/suggest",     # 프로젝트명 fuzzy match
]
ok(open_gets == KNOWN,
   "로그인 없이 열리는 /admin 읽기 주소가 달라졌다.\n"
   "    지금: %s\n    알고 있던 것: %s\n"
   "    늘었다면 일부러 그런 것인지 확인하고, 맞으면 이 목록에 적어 두세요."
   % (open_gets, KNOWN))


# ── 4. 화면이 저장 실패를 삼키지 않는가 ─────────────────────────────
AV2 = (BACK / "admin_v2.html").read_text(encoding="utf-8")
i = AV2.find("'/types', {")
ok(i > 0, "화면에서 유형 저장을 부르는 데를 못 찾았다")
if i > 0:
    blk = AV2[i:i + 900]
    ok("credentials" in blk, "유형 저장이 쿠키를 보낸다고 적혀 있지 않다")
    ok("401" in blk,
       "401 을 걸러내지 않는다 — 로그인이 풀린 채로 고치면 조용히 사라진다")


if FAIL:
    print("실패 %d건" % len(FAIL))
    for f in FAIL:
        print("  -", f)
    raise SystemExit(1)
print("전부 통과 · 라우트 %d개 · /admin 쓰기 구멍 0 · 열린 /admin 읽기 %d개"
      % (len(routes), len(open_gets)))
