# Use Debian Bookworm (Playwright supports it well) instead of trixie
FROM python:3.11-slim-bookworm

ENV PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1 \
    DEBIAN_FRONTEND=noninteractive \
    PLAYWRIGHT_BROWSERS_PATH=0

WORKDIR /app

# System deps:
# - Tesseract + langs
# - Chromium runtime deps for Playwright on Debian
# - Fonts that actually exist on Debian (fonts-ubuntu, fonts-unifont, fonts-liberation)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl gnupg ca-certificates \
    tesseract-ocr tesseract-ocr-heb tesseract-ocr-eng \
    # Chromium / Playwright runtime deps
    libasound2 libatk-bridge2.0-0 libatk1.0-0 libc6 libcups2 libdbus-1-3 \
    libdrm2 libgbm1 libglib2.0-0 libgtk-3-0 libnspr4 libnss3 libu2f-udev \
    libx11-6 libx11-xcb1 libxcb1 libxcomposite1 libxdamage1 libxext6 \
    libxfixes3 libxrandr2 libxshmfence1 libxkbcommon0 \
    libpango-1.0-0 libpangocairo-1.0-0 libatspi2.0-0 \
    fonts-liberation fonts-dejavu-core fonts-noto \
    wget xdg-utils \
 && rm -rf /var/lib/apt/lists/*

# Python deps
COPY requirements.txt .
RUN pip install -r requirements.txt

# Install only the browser binaries (deps already provided above)
RUN playwright install chromium

# Copy the rest and set the default command as you had it
COPY . .

# Example:
# CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
