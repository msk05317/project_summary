FROM python:3.11-slim

WORKDIR /app

# 한글 폰트 (엑셀→PNG 변환 시 한글 깨짐 방지)
RUN apt-get update && apt-get install -y --no-install-recommends fonts-noto-cjk && rm -rf /var/lib/apt/lists/*

# requirements.txt는 backend/ 안에 있음
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# backend 전체 복사
COPY backend/ .

# 데이터 디렉토리
RUN mkdir -p /app/data

EXPOSE 8080

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
