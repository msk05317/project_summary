#!/bin/sh
# 운영 데이터를 내 컴퓨터로 내려받는다.
#
#   ./backup.sh
#
# 받는 것
#   backups/models_<시각>.json     모델·주차별 계획·공정·보드 입력값 (제일 중요)
#   backups/models_<시각>.shape    그 안에 뭐가 몇 개 들어있는지 요약
#   backups/photos_<시각>.tgz      노트/주차별 계획 사진 (없으면 건너뜀)
#
# 받은 뒤 반드시 shape 를 눈으로 확인할 것. 0 바이트나 깨진 JSON 이면
# 이 스크립트가 먼저 실패하지만, '프로젝트가 몇 개인지'는 사람만 안다.
set -e

APP=project-summary-mkoo
DIR=$(cd "$(dirname "$0")" && pwd)
OUT="$DIR/backups"
STAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p "$OUT"

command -v flyctl >/dev/null 2>&1 || { echo "flyctl 이 없습니다."; exit 1; }

echo "==> models.json 받는 중..."
flyctl ssh console -a "$APP" -C "cat /data/models.json" > "$OUT/models_$STAMP.json"

python3 - "$OUT/models_$STAMP.json" "$OUT/models_$STAMP.shape" <<'PY'
import json, sys, os

src, dst = sys.argv[1], sys.argv[2]
raw = open(src, encoding='utf-8-sig', errors='replace').read()
# flyctl 이 앞에 접속 안내문을 붙이는 경우가 있어 첫 '{' 부터 자른다
i = raw.find('{')
if i > 0:
    raw = raw[i:]
    open(src, 'w', encoding='utf-8').write(raw)
if i < 0:
    print('내려받은 파일에 JSON 이 없습니다. flyctl 로그인 상태를 확인하세요.')
    os.remove(src); sys.exit(1)

data = json.loads(raw)          # 깨졌으면 여기서 죽는다
projects = data.get('projects') or {}
if not projects:
    print('프로젝트가 하나도 없습니다 — 백업하지 않습니다.')
    os.remove(src); sys.exit(1)

lines, tm, tw = [], 0, 0
for key in sorted(projects):
    proj = projects[key] or {}
    ms = proj.get('models') or []
    weeks = sum(len(wk or {}) for m in ms if isinstance(m, dict)
                for wk in (m.get('weekly_plan') or {}).values())
    proc = sum(1 for m in ms if isinstance(m, dict) and (m.get('process') or []))
    note = sum(1 for m in ms if isinstance(m, dict) and str(m.get('note') or '').strip())
    tm += len(ms); tw += weeks
    lines.append(f'{key:24} 모델 {len(ms):4}  주차 {weeks:5}  공정 {proc:4}  메모 {note:4}')
lines.append(f'{"합계":24} 모델 {tm:4}  주차 {tw:5}')
body = '\n'.join(lines)
open(dst, 'w', encoding='utf-8').write(body + '\n')
print(body)
print(f'\n{os.path.getsize(src):,} 바이트  ->  {src}')
PY

echo "==> 사진 받는 중 (없으면 건너뜁니다)..."
if flyctl ssh console -a "$APP" -C "tar czf - -C /data note_photos" > "$OUT/photos_$STAMP.tgz" 2>/dev/null \
   && tar tzf "$OUT/photos_$STAMP.tgz" >/dev/null 2>&1; then
  echo "    $(tar tzf "$OUT/photos_$STAMP.tgz" | wc -l | tr -d ' ') 개"
else
  rm -f "$OUT/photos_$STAMP.tgz"
  echo "    사진은 못 받았습니다 (models.json 은 받았습니다)"
fi

echo
echo "완료: $OUT"
ls -lh "$OUT" | tail -5
