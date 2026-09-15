#!/usr/bin/env bash
# OneView 앱 릴리스 — 빌드부터 배포까지.
#
#   ./release.sh                  → 끝자리 버전을 올린다 (2.3.0 → 2.3.1)
#   ./release.sh 2.4.0 30         → 버전·코드를 지정
#   ./release.sh --same           → 지금 버전 그대로 (APK 만 다시 올릴 때)
#
# 기본이 '올린다' 인 이유: 버전이 그대로면 앱에 업데이트 팝업이 안 뜬다.
# 올려놓고 왜 안 뜨지 하고 한참 찾은 적이 있다.
#
# 하는 일
#   1) 버전 올리기 (인자를 주면 그 값으로)
#   2) APK 빌드
#   3) 우리 서버에 APK 올리기 (/admin/app/release)
#   4) app_version.json 을 그 버전으로 맞추고 커밋 + push
#
# 3번을 GitHub 릴리스로 하던 때가 있었는데, 저장소를 비공개로 돌린 뒤로는
# 앱이 그 주소에서 파일을 못 받는다 (404). 그래서 우리 서버로 올린다.
# 서버에 APK 가 있으면 /app/version 이 받는 곳을 /app/download 로 돌려준다.
#
# 관리자 비밀번호는 ONEVIEW_ADMIN_PW 로 주거나, 물어보면 입력하면 된다.
set -euo pipefail
cd "$(dirname "$0")"

step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
die()  { printf '\n\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

command -v flutter >/dev/null || die "flutter 가 없습니다."

# ── 1. 버전
PUBSPEC=mobile/pubspec.yaml
LINE=$(grep '^version:' "$PUBSPEC" | head -1 | sed 's/version: *//')
CUR_VER="${LINE%%+*}"; CUR_CODE="${LINE##*+}"
[ -n "$CUR_VER" ] && [ -n "$CUR_CODE" ] || die "pubspec 에서 버전을 못 읽었습니다."

if [ "${1:-}" = "--same" ]; then
  VER="$CUR_VER"; CODE="$CUR_CODE"
  echo "버전을 그대로 둡니다 ($VER+$CODE). 기존 사용자에게는 팝업이 안 뜹니다."
elif [ $# -ge 2 ]; then
  VER="$1"; CODE="$2"
else
  # 끝자리 +1
  VER="${CUR_VER%.*}.$(( ${CUR_VER##*.} + 1 ))"
  CODE=$(( CUR_CODE + 1 ))
  echo "버전을 올립니다: $CUR_VER+$CUR_CODE → $VER+$CODE"
fi

if [ "$VER+$CODE" != "$CUR_VER+$CUR_CODE" ]; then
  perl -pi -e "s/^version: .*/version: $VER+$CODE/" "$PUBSPEC"
fi

# 이미 배포된 버전과 같으면 팝업이 안 뜬다. 미리 잡는다.
PREV=$(python3 -c "import json;d=json.load(open('backend/app_version.json'));print(d['latest_version']+'+'+str(d['latest_version_code']))")
if [ "$VER+$CODE" = "$PREV" ] && [ "${1:-}" != "--same" ]; then
  die "$VER+$CODE 는 이미 배포된 버전입니다. 버전을 올리거나 --same 을 주세요."
fi

TAG="v$VER"
NOTES=$(python3 -c "import json;print(json.load(open('backend/app_version.json'))['release_notes'])")
step "릴리스 $TAG (코드 $CODE)"
printf '  릴리스 노트: %s\n' "$(printf '%s' "$NOTES" | head -1)"
printf '  (바꾸려면 backend/app_version.json 의 release_notes 를 고치고 다시 실행)\n'

# ── 2. 빌드
step "APK 빌드"
[ -f mobile/android/key.properties ] || cat <<'WARN'
  ! key.properties 가 없어 debug 키로 서명됩니다.
    이 맥에서 계속 빌드하는 동안은 문제없지만, PC 를 바꾸거나
    debug 키가 새로 생기면 기존 사용자가 업데이트를 설치할 수 없습니다.
WARN
( cd mobile && flutter build apk --release )
APK=mobile/build/app/outputs/flutter-apk/app-release.apk
[ -f "$APK" ] || die "APK 가 안 만들어졌습니다: $APK"
echo "  $(du -h "$APK" | cut -f1)  $APK"

# ── 3. 우리 서버에 APK 올리기  ← 이게 돼야 앱이 받는다
step "서버에 APK 올리기"
API="${ONEVIEW_API:-https://project-summary-mkoo.fly.dev}"
PW="${ONEVIEW_ADMIN_PW:-}"
if [ -z "$PW" ]; then
  printf '  관리자 비밀번호: '
  read -rs PW
  echo
fi
[ -n "$PW" ] || die "비밀번호가 없으면 APK 를 못 올립니다."

COOKIE=$(mktemp)
trap 'rm -f "$COOKIE"' EXIT
curl -sS -c "$COOKIE" -o /dev/null -w '%{http_code}' \
     -F "password=$PW" "$API/admin/login" | grep -q '^200$' \
  || die "관리자 로그인 실패 (비밀번호 확인)"

RESP=$(curl -sS -b "$COOKIE" \
  -F "file=@$APK" \
  -F "latest_version=$VER" \
  -F "latest_version_code=$CODE" \
  -F "release_notes=$NOTES" \
  "$API/admin/app/release")
echo "$RESP" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print('  서버 응답을 읽을 수 없습니다'); raise SystemExit(1)
if not d.get('ok'):
    print('  실패:', d.get('detail') or d); raise SystemExit(1)
v = d.get('version') or {}
print(f\"  {v.get('latest_version')}+{v.get('latest_version_code')} · APK {d.get('apk_bytes',0)/1048576:.1f} MB 올렸습니다\")
" || die "APK 업로드 실패"

# 실제로 받아지는지 확인한다. 여기서 막히면 앱도 못 받는다.
DL=$(curl -sS -o /dev/null -w '%{http_code}' -r 0-1024 "$API/app/download" || echo 000)
case "$DL" in
  200|206) echo "  받기 확인 OK ($API/app/download)" ;;
  *) die "APK 를 서버에서 못 받습니다 (HTTP $DL). 앱도 못 받습니다." ;;
esac

# ── 4. 버전 파일 맞추고 push  ← 이게 올라가야 팝업이 뜬다
step "app_version.json 갱신 + push"
python3 - "$VER" "$CODE" <<'PY'
import json, sys, pathlib
ver, code = sys.argv[1], int(sys.argv[2])
p = pathlib.Path('backend/app_version.json')
d = json.loads(p.read_text(encoding='utf-8'))
# 받는 곳은 우리 서버. 비공개 저장소의 릴리스 주소는 앱이 못 받는다.
d.update({'latest_version': ver, 'latest_version_code': code,
          'download_url': '/app/download', 'apk_url': '/app/download'})
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f'  {ver}+{code}')
PY
git add backend/app_version.json "$PUBSPEC"
git diff --cached --quiet || git commit -m "release $TAG"
git push

printf '\n\033[32m✓ %s 배포 완료. 앱을 켜면 업데이트 팝업이 뜹니다.\033[0m\n' "$TAG"
printf '  확인: %s/app/version\n' "$API"
