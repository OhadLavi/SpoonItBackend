# ✅ Use Playwright's official Python base image (includes Chromium + deps)
# Note: Playwright Docker images use 3-segment versions (v1.47.0), not 4-segment (v1.47.1)
FROM mcr.microsoft.com/playwright/python:v1.47.0-jammy

# Workdir
WORKDIR /app

# Install OCR languages (Hebrew + English)
RUN apt-get update && apt-get install -y --no-install-recommends \
    tesseract-ocr tesseract-ocr-heb tesseract-ocr-eng \
 && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt ./

# IMPORTANT:
# - Do NOT list `playwright` in requirements.txt when using this base image.
#   (The image already has a matching Playwright version + browsers.)
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# App code
COPY . .

# Cloud Run sets PORT; default to 8080 locally
ENV PYTHONUNBUFFERED=1
EXPOSE 8080

# Run FastAPI with Uvicorn and bind to $PORT (Cloud Run requirement)
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8080}"]
