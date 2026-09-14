#!/bin/sh
# 운영 데이터를 내 컴퓨터로 내려받는다.
#
#   ./backup.sh
#
# 받는 것 (앞에 있는 게 더 중요하다)
#   backups/models_<시각>.json     models.json 원본 — 이것만이 그대로 되돌릴 수 있다
#   backups/models_<시각>.shape    프로젝트별 모델·주차·공정·메모 개수
#   backups/photos_<시각>.tgz      노트/주차별 계획 사진
#   backups/api_<시각>.json        공개 API 스냅샷 — flyctl 없이도 받는다
#   backups/api_<시각>.shape
#
# api_ 쪽은 '지금 화면에 보이는 값'의 사본이다. 되돌리기용은 아니지만
# 무엇이 언제 사라졌는지 비교할 근거는 된다.
#
# 한 단계가 실패해도 나머지는 계속한다. 끝에 무엇을 못 받았는지 알려준다.
# 0 바이트·깨진 JSON·프로젝트 0개면 그 파일은 저장하지 않는다.

APP=project-summary-mkoo
DIR=$(cd "$(dirname "$0")" && pwd)
OUT="$DIR/backups"
STAMP=$(date +%Y%m%d_%H%M%S)
FAILED=""
mkdir -p "$OUT"

# ── 1. models.json 원본 ───────────────────────────────────────────
if command -v flyctl >/dev/null 2>&1; then
  echo "==> models.json 원본 받는 중..."
  if flyctl ssh console -a "$APP" -C "cat /data/models.json" > "$OUT/models_$STAMP.json" 2>/dev/null; then
    python3 - "$OUT/models_$STAMP.json" "$OUT/models_$STAMP.shape" <<'PY' || FAILED="$FAILED models.json"
import json, os, sys

src, dst = sys.argv[1], sys.argv[2]
raw = open(src, encoding='utf-8-sig', errors='replace').read()
# flyctl 이 앞에 접속 안내문("Connecting to fdaa:...")을 붙인다
i = raw.find('{')
if i < 0:
    print('   내려받은 파일에 JSON 이 없습니다. flyctl 로그인 상태를 확인하세요.')
    os.remove(src); sys.exit(1)
if i > 0:
    raw = raw[i:]
    open(src, 'w', encoding='utf-8').write(raw)

try:
    data = json.loads(raw)
except Exception as e:
    print(f'   JSON 이 깨졌습니다: {e}')
    os.remove(src); sys.exit(1)

projects = data.get('projects') or {}
if not projects:
    print('   프로젝트가 하나도 없습니다 — 저장하지 않습니다.')
    os.remove(src); sys.exit(1)

lines, tm, tw = [], 0, 0
for key in sorted(projects):
    ms = (projects[key] or {}).get('models') or []
    weeks = sum(len(wk or {}) for m in ms if isinstance(m, dict)
                for wk in (m.get('weekly_plan') or {}).values())
    proc = sum(1 for m in ms if isinstance(m, dict) and (m.get('process') or []))
    note = sum(1 for m in ms if isinstance(m, dict) and str(m.get('note') or '').strip())
    tm += len(ms); tw += weeks
    lines.append(f'{key:<26} 모델 {len(ms):>4}  주차 {weeks:>5}  공정 {proc:>4}  메모 {note:>4}')
lines.append(f'{"합계":<24} 모델 {tm:>4}  주차 {tw:>5}')
body = '\n'.join(lines)
open(dst, 'w', encoding='utf-8').write(body + '\n')
print(body)
print(f'\n   {os.path.getsize(src):,} 바이트  ->  {src}')
PY
  else
    rm -f "$OUT/models_$STAMP.json"
    echo "   flyctl 로 접속하지 못했습니다."
    FAILED="$FAILED models.json"
  fi

  # ── 2. 사진 ─────────────────────────────────────────────────────
  # ssh console 로 tar 를 그대로 흘리면 깨진다. 서버에서 먼저 묶고 sftp 로 받는다.
  echo "==> 사진 받는 중..."
  if flyctl ssh console -a "$APP" -C "tar czf /tmp/np_$STAMP.tgz -C /data note_photos" >/dev/null 2>&1 \
     && flyctl ssh sftp get "/tmp/np_$STAMP.tgz" "$OUT/photos_$STAMP.tgz" >/dev/null 2>&1 \
     && tar tzf "$OUT/photos_$STAMP.tgz" >/dev/null 2>&1; then
    echo "   $(tar tzf "$OUT/photos_$STAMP.tgz" | wc -l | tr -d ' ') 개"
  else
    rm -f "$OUT/photos_$STAMP.tgz"
    echo "   사진은 못 받았습니다 (원래 없을 수도 있습니다)"
    FAILED="$FAILED 사진"
  fi
  flyctl ssh console -a "$APP" -C "rm -f /tmp/np_$STAMP.tgz" >/dev/null 2>&1
else
  echo "==> flyctl 이 없어 models.json 원본은 건너뜁니다."
  FAILED="$FAILED models.json(flyctl없음)"
fi

# ── 3. 공개 API 스냅샷 ────────────────────────────────────────────
echo
echo "==> 공개 API 스냅샷 받는 중..."
python3 "$DIR/tools_pull_api.py" "$OUT" || FAILED="$FAILED API스냅샷"

echo
if [ -n "$FAILED" ]; then
  echo "!! 못 받은 것:$FAILED"
fi
echo "완료: $OUT"
ls -lht "$OUT" | head -7
