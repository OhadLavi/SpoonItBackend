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

# Copy installed Python packages from builder
COPY --from=builder /root/.local /home/appuser/.local

# Copy application code into container
COPY --chown=appuser:appuser . .

# Expose Python user base executables
ENV PATH="/home/appuser/.local/bin:${PATH}"

# Switch to non-root user
USER appuser

# Expose port for Cloud Run
EXPOSE 8080

# Health check—internal self test (NO heredoc, works on Cloud Build)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python3 -c "import httpx, sys; sys.exit(0 if httpx.get('http://localhost:8080/health', timeout=3).status_code == 200 else 1)"

# Gunicorn command (fast cold start)
CMD [
  "gunicorn", "app.main:app",
  "--workers", "1",
  "--worker-class", "uvicorn.workers.UvicornWorker",
  "--bind", "0.0.0.0:8080",
  "--timeout", "0",
  "--graceful-timeout", "30",
  "--access-logfile", "-",
  "--error-logfile", "-"
]
