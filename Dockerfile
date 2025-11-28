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

# Copy application code
COPY --chown=appuser:appuser . .

# Ensure local bin is in PATH
ENV PATH="/home/appuser/.local/bin:${PATH}"

# Run as non-root
USER appuser

# Expose port for Cloud Run
EXPOSE 8080

# Health check — simple, single line (no heredoc)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python3 -c "import sys, httpx; sys.exit(0 if httpx.get('http://localhost:8080/health', timeout=3).status_code == 200 else 1)"

# Start app with gunicorn (single-line CMD, JSON array)
CMD ["gunicorn", "app.main:app", "--workers", "1", "--worker-class", "uvicorn.workers.UvicornWorker", "--bind", "0.0.0.0:8080", "--timeout", "0", "--graceful-timeout", "30", "--access-logfile", "-", "--error-logfile", "-"]
