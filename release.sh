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
#   3) GitHub 릴리스에 APK 올리기
#        gh 가 되면 자동, 안 되면 브라우저와 Finder 를 열어 주고 기다린다
#   4) app_version.json 을 그 버전으로 맞추고 커밋 + push
#
# 4번이 올라가야 기존 사용자 앱에 업데이트 팝업이 뜬다.
# 그래서 APK 가 올라간 걸 확인한 다음에만 push 한다 — 순서가 뒤집히면
# 그 사이에 앱을 켠 사람이 없는 파일을 받으러 간다.
set -euo pipefail
cd "$(dirname "$0")"

REPO=msk05317/project_summary
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

# ── 3. 릴리스에 APK 올리기
step "GitHub 릴리스에 APK 올리기"
UPLOADED=0
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "  $TAG 가 이미 있습니다. 파일만 덮어씁니다."
    gh release upload "$TAG" "$APK" --repo "$REPO" --clobber && UPLOADED=1
  else
    gh release create "$TAG" "$APK" --repo "$REPO" --title "$TAG" --notes "$NOTES" && UPLOADED=1
  fi
fi

if [ "$UPLOADED" = 0 ]; then
  # gh 가 안 되는 경우(회사망에서 TLS 를 가로채면 인증서 검증이 막힌다).
  # 브라우저는 그 인증서를 믿으므로 손으로 올리면 된다.
  URL=$(python3 - "$TAG" "$NOTES" <<'PY'
import sys, urllib.parse
tag, notes = sys.argv[1], sys.argv[2]
q = urllib.parse.urlencode({'tag': tag, 'title': tag, 'body': notes})
print(f'https://github.com/msk05317/project_summary/releases/new?{q}')
PY
)
  cat <<EOF
  gh 로는 못 올립니다. 브라우저로 올려 주세요.

    1) 방금 연 Finder 창의 app-release.apk 를
    2) 방금 연 GitHub 페이지 아래 'Attach binaries' 칸에 끌어다 놓고
    3) 'Publish release' 를 누르세요. (태그·제목·내용은 채워져 있습니다)
EOF
  open -R "$APK" 2>/dev/null || true
  open "$URL" 2>/dev/null || echo "  $URL"
  printf '\n  다 올리셨으면 Enter, 그만두려면 Ctrl+C: '
  read -r _
  echo "  확인했습니다."
fi

# ── 4. 버전 파일 맞추고 push  ← 이게 올라가야 팝업이 뜬다
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

printf '\n\033[32m✓ %s 배포 완료. 앱을 켜면 업데이트 팝업이 뜹니다.\033[0m\n' "$TAG"
printf '  확인: https://raw.githubusercontent.com/%s/main/backend/app_version.json\n' "$REPO"
