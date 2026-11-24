# syntax=docker/dockerfile:1.7

# ── Stage 1: builder ──────────────────────────────────────────────────────────
FROM python:3.12.7-slim@sha256:af4e85f1cac90dd3771e47292ea7c8a9830abfabbe4faa5c3bb158f2f7a1c4e2 AS builder

WORKDIR /app

# Install only production deps into a clean prefix
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Stage 2: final (distroless-equivalent with Alpine) ───────────────────────
FROM python:3.12.7-alpine3.20@sha256:7c2a9a5ccced089b44f69b78a7e08bd46af78e7a37f9d5cb8f9a41cead02a6e6

LABEL org.opencontainers.image.title="devops-task-service" \
      org.opencontainers.image.description="DevOps assessment web service" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.source="https://github.com/YOUR_ORG/devops-task" \
      org.opencontainers.image.licenses="MIT"

# Non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /install /usr/local
# Copy application code
COPY --chown=appuser:appgroup . .

USER appuser

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:8080/health || exit 1

ENV PORT=8080 \
    LOG_LEVEL=info \
    ENV_NAME=production \
    APP_VERSION=1.0.0 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

ENTRYPOINT ["python", "-m", "uvicorn", "main:app", \
            "--host", "0.0.0.0", \
            "--port", "8080", \
            "--no-access-log"]
