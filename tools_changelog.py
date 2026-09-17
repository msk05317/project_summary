#!/usr/bin/env python3
"""CHANGELOG.md 에서 한 버전의 노트를 꺼낸다.

release.sh 와 app_version.json 갱신이 같이 쓴다. 서버(backend/main.py)에도
같은 파싱이 있는데, 거기는 요청마다 읽어야 해서 따로 둔다 — 규칙은 하나다:

    ## 2.3.10 — 2026-09-16
    <여기부터 다음 ## 전까지가 그 버전의 노트>

    python3 tools_changelog.py 2.3.10
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).parent.resolve()


def notes_for(version: str, path=None) -> str:
    """그 버전의 본문. 없으면 빈 문자열."""
    p = pathlib.Path(path) if path else (ROOT / "CHANGELOG.md")
    if not p.exists():
        return ""
    want = str(version or "").strip().lstrip("vV")
    cur, body = None, []
    for line in p.read_text(encoding="utf-8").split("\n"):
        m = re.match(r"^##\s+(\S+)", line.rstrip())
        if m:
            if cur == want:          # 다음 버전 머리를 만났다 — 여기까지
                break
            cur = m.group(1).lstrip("vV")
            body = []
            continue
        if cur == want:
            body.append(line)
    return "\n".join(body).strip()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("사용법: tools_changelog.py <버전>")
    print(notes_for(sys.argv[1]))
