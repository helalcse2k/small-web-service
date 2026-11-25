# syntax=docker/dockerfile:1.7

# ── Stage 1: builder ──────────────────────────────────────────────────────────
FROM python:3.12.7-alpine3.20@sha256:5049c050bdc68575a10bcb1885baa0689b6c15152d8a56a7e399fb49f783bf98 AS builder

WORKDIR /app

# Build tools only in builder stage (not in final image)
# hadolint ignore=DL3018
RUN apk add --no-cache gcc musl-dev libffi-dev

# Install only production deps into a clean prefix
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Stage 2: final (minimal Alpine) ───────────────────────────────────────────
FROM python:3.12.7-alpine3.20@sha256:5049c050bdc68575a10bcb1885baa0689b6c15152d8a56a7e399fb49f783bf98

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
