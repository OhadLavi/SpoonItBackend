# Use Python 3.11 slim
FROM python:3.11-slim

# Faster, cleaner installs
ENV PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# System deps for Playwright (Chromium) + Tesseract (heb+eng)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl gnupg ca-certificates \
    tesseract-ocr tesseract-ocr-heb tesseract-ocr-eng \
    && rm -rf /var/lib/apt/lists/*

# Python deps
COPY requirements.txt .
RUN pip install -r requirements.txt

# Install Chromium and all native libraries in one shot
# (Playwright team’s recommended way for Docker)
RUN playwright install --with-deps chromium

# App code
COPY . .

# Cloud Run: listen on 0.0.0.0:$PORT (PORT is injected)
EXPOSE 8080
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8080}"]
