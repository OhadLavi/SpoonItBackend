# ============================
# Stage 1 — Build environment
# ============================
FROM python:3.11-slim AS builder

WORKDIR /app

# Install build-time dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install to local user dir
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt


# ============================
# Stage 2 — Runtime environment
# ============================
FROM python:3.11-slim

WORKDIR /app

# Create non-root user
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app

# Copy installed Python packages from builder
COPY --from=builder /root/.local /home/appuser/.local

# Install playwright browser dependencies (needed for headless browser support)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libdbus-1-3 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libasound2 \
    && rm -rf /var/lib/apt/lists/*

# Copy application code
COPY --chown=appuser:appuser . .

# Ensure local bin is in PATH
ENV PATH="/home/appuser/.local/bin:${PATH}"

# Run as non-root
USER appuser

# Install playwright browsers (must be done as appuser)
RUN playwright install chromium
RUN playwright install-deps chromium || true

# Expose port for Cloud Run
EXPOSE 8080

# Health check — simple, single line (no heredoc)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python3 -c "import sys, httpx; sys.exit(0 if httpx.get('http://localhost:8080/health', timeout=3).status_code == 200 else 1)"

# Start app with gunicorn (single-line CMD, JSON array)
# --access-logfile -: Disable access logs (we have our own request logging middleware)
# --error-logfile -: Send errors to stderr (but we set gunicorn logger to WARNING to reduce noise)
# --log-level warning: Only log warnings and above from gunicorn itself
CMD ["gunicorn", "app.main:app", "--workers", "4", "--worker-class", "uvicorn.workers.UvicornWorker", "--bind", "0.0.0.0:8080", "--timeout", "300", "--graceful-timeout", "60", "--access-logfile", "-", "--error-logfile", "-", "--log-level", "warning"]
