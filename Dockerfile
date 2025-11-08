FROM python:3.11-slim
WORKDIR /app

# Tools and OCR languages
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl gnupg ca-certificates tesseract-ocr tesseract-ocr-heb tesseract-ocr-eng \
  && rm -rf /var/lib/apt/lists/*

# Python deps
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
 && pip install --no-cache-dir playwright==1.47.1

# ✅ Install Chromium AND all required system libraries via Playwright
RUN playwright install --with-deps chromium

COPY . .
ENV PYTHONUNBUFFERED=1
EXPOSE 8080
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8080}"]
