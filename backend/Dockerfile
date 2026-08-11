# Python 3.11 슬림 베이스
FROM python:3.11-slim

# 시스템 패키지: LibreOffice + Java (LibreOffice가 스타일 렌더링에 사용) + Poppler + 폰트
RUN apt-get update && apt-get install -y --no-install-recommends \
    libreoffice \
    libreoffice-impress \
    libreoffice-calc \
    default-jre-headless \
    poppler-utils \
    fonts-nanum \
    fonts-noto-cjk \
    fonts-noto-cjk-extra \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# requirements.txt 먼저 복사해서 캐시 활용
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# 앱 코드 복사
COPY . .

# Railway가 PORT 환경변수를 자동으로 줌
ENV PORT=8000
EXPOSE 8000

# 영구 저장 경로 (Volume 마운트 예정)
RUN mkdir -p /data/uploads /data/slides /data/slide_images /data/cropped /data/custom_images

# uvicorn 실행
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}"]
