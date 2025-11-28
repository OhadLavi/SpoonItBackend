# ============================
# Stage 1 — Build environment
# ============================
FROM python:3.11-slim as builder

WORKDIR /app

# Install build-time dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

# Install Python packages into local user folder
RUN pip install --no-cache-dir --user -r requirements.txt


# ============================
# Stage 2 — Runtime environment
# ============================
FROM python:3.11-slim

WORKDIR /app

# Create a non-root user
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app

# Copy installed Python packages
COPY --from=builder /root/.local /home/appuser/.local

# Copy application code
COPY --chown=appuser:appuser . .

# Add local bin path
ENV PATH="/home/appuser/.local/bin:${PATH}"

USER appuser

# Cloud Run port
EXPOSE 8080

# Health check (internal)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python - <<EOF
import httpx; httpx.get("http://localhost:8080/health", timeout=3)
EOF

# Run app with Gunicorn + Uvicorn worker
CMD [
  "gunicorn", "app.main:app",
  "--workers", "1",                          # Faster cold start, Cloud Run autoscale handles load
  "--worker-class", "uvicorn.workers.UvicornWorker",
  "--bind", "0.0.0.0:8080",
  "--timeout", "0",
  "--graceful-timeout", "30",
  "--access-logfile", "-",
  "--error-logfile", "-"
]
