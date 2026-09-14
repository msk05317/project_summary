#!/usr/bin/env bash
# OneView 앱 릴리스 — 빌드부터 배포까지 한 번에.
#
#   ./release.sh                  → pubspec 버전 그대로
#   ./release.sh 2.3.1 24         → 버전·코드를 지정
#
# 하는 일
#   1) pubspec 버전 확인 (인자를 주면 그 값으로 고쳐 쓴다)
#   2) APK 빌드
#   3) GitHub 릴리스 만들고 APK 올리기
#   4) app_version.json 을 그 버전으로 맞추고 커밋 + push
#   5) 서버가 배포돼 있으면 APK 를 서버에도 올린다 (저장소를 비공개로
#      돌린 뒤에도 앱이 받을 수 있게)
#
# 4번까지 끝나면 기존 사용자가 앱을 켤 때 업데이트 팝업이 뜬다.
set -euo pipefail
cd "$(dirname "$0")"

step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
die()  { printf '\n\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

command -v flutter >/dev/null || die "flutter 가 없습니다."
command -v gh >/dev/null || die "gh(GitHub CLI)가 없습니다.  brew install gh && gh auth login"
gh auth status >/dev/null 2>&1 || die "gh 로그인이 안 돼 있습니다.  gh auth login"

# ── 1. 버전
PUBSPEC=mobile/pubspec.yaml
if [ $# -ge 2 ]; then
  VER="$1"; CODE="$2"
  perl -pi -e "s/^version: .*/version: $VER+$CODE/" "$PUBSPEC"
  echo "pubspec 버전을 $VER+$CODE 로 바꿨습니다."
else
  LINE=$(grep '^version:' "$PUBSPEC" | head -1 | sed 's/version: *//')
  VER="${LINE%%+*}"; CODE="${LINE##*+}"
fi
[ -n "$VER" ] && [ -n "$CODE" ] || die "pubspec 에서 버전을 못 읽었습니다."
TAG="v$VER"
step "릴리스 $TAG (코드 $CODE)"

gh release view "$TAG" >/dev/null 2>&1 && \
  die "$TAG 릴리스가 이미 있습니다. 버전을 올리세요:  ./release.sh 2.3.1 24"

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
echo "  $(du -h "$APK" | cut -f1)"

# ── 3. 변경 내용 (app_version.json 에 적어둔 걸 그대로 쓴다)
NOTES=$(python3 -c "import json;print(json.load(open('backend/app_version.json'))['release_notes'])")

# ── 4. GitHub 릴리스
step "GitHub 릴리스 올리기"
gh release create "$TAG" "$APK" --title "$TAG" --notes "$NOTES"

# ── 5. 버전 파일 맞추고 push  ← 이게 올라가야 팝업이 뜬다
step "app_version.json 갱신 + push"
python3 - "$VER" "$CODE" <<'PY'
import json, sys, pathlib
ver, code = sys.argv[1], int(sys.argv[2])
p = pathlib.Path('backend/app_version.json')
d = json.loads(p.read_text(encoding='utf-8'))
url = f'https://github.com/msk05317/project_summary/releases/download/v{ver}/app-release.apk'
d.update({'latest_version': ver, 'latest_version_code': code,
          'download_url': url, 'apk_url': url})
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f'  {ver}+{code}')
PY
git add backend/app_version.json "$PUBSPEC"
git diff --cached --quiet || git commit -m "release $TAG"
git push

# ── 6. 서버에도 올려 둔다 (있으면)
step "서버에 APK 올리기 (선택)"
BASE=https://project-summary-mkoo.fly.dev
if [ -n "${ONEVIEW_ADMIN_COOKIE:-}" ]; then
  curl -sS -X POST "$BASE/admin/app/release" \
    -H "Cookie: admin_auth=$ONEVIEW_ADMIN_COOKIE" \
    -F "file=@$APK" -F "latest_version=$VER" -F "latest_version_code=$CODE" \
    -F "release_notes=$NOTES" | head -c 300
  echo
else
  echo "  건너뜀 — $BASE/admin/app 에서 직접 올리셔도 됩니다."
  echo "  (저장소를 비공개로 돌릴 거면 이 단계가 필요합니다)"
fi

printf '\n\033[32m✓ %s 배포 완료. 앱을 켜면 업데이트 팝업이 뜹니다.\033[0m\n' "$TAG"
