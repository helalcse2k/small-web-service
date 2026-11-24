"""
Production-grade FastAPI web service for DevOps assessment.
Reads configuration from environment variables, emits structured JSON logs,
exposes Prometheus metrics, and shuts down gracefully on SIGTERM.
"""

import logging
import os
import signal
import sys
import time
from contextlib import asynccontextmanager

import structlog
import uvicorn
from fastapi import FastAPI, Request, Response
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Histogram,
    generate_latest,
)

# ── Configuration from env vars ────────────────────────────────────────────────
PORT = int(os.getenv("PORT", "8080"))
LOG_LEVEL = os.getenv("LOG_LEVEL", "info").upper()
ENV_NAME = os.getenv("ENV_NAME", "development")
APP_VERSION = os.getenv("APP_VERSION", "1.0.0")

# ── Structured JSON logging ────────────────────────────────────────────────────
structlog.configure(
    processors=[
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.stdlib.add_log_level,
        structlog.processors.JSONRenderer(),
    ],
    wrapper_class=structlog.BoundLogger,
    context_class=dict,
    logger_factory=structlog.PrintLoggerFactory(),
)
log = structlog.get_logger()

# Standard stdlib logging → structlog bridge
logging.basicConfig(
    format="%(message)s",
    stream=sys.stdout,
    level=getattr(logging, LOG_LEVEL, logging.INFO),
)

# ── Prometheus metrics ─────────────────────────────────────────────────────────
REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP request count",
    ["method", "endpoint", "status_code"],
)
ERROR_COUNT = Counter(
    "http_errors_total",
    "Total HTTP error count",
    ["method", "endpoint"],
)
REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "endpoint"],
    buckets=[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
)

# ── Graceful shutdown ─────────────────────────────────────────────────────────
_shutdown = False


def _handle_sigterm(signum, frame):  # noqa: ANN001
    global _shutdown
    log.info("sigterm_received", signal=signum)
    _shutdown = True


signal.signal(signal.SIGTERM, _handle_sigterm)
signal.signal(signal.SIGINT, _handle_sigterm)


# ── App lifespan ──────────────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):  # noqa: ANN001
    log.info("startup", version=APP_VERSION, env=ENV_NAME, port=PORT)
    yield
    log.info("shutdown", version=APP_VERSION)


app = FastAPI(title="DevOps Task Service", version=APP_VERSION, lifespan=lifespan)


# ── Middleware: metrics & logging ──────────────────────────────────────────────
@app.middleware("http")
async def metrics_middleware(request: Request, call_next):  # noqa: ANN001
    start = time.perf_counter()
    response = await call_next(request)
    duration = time.perf_counter() - start

    endpoint = request.url.path
    method = request.method
    status = response.status_code

    REQUEST_COUNT.labels(method=method, endpoint=endpoint, status_code=status).inc()
    REQUEST_LATENCY.labels(method=method, endpoint=endpoint).observe(duration)

    if status >= 500:
        ERROR_COUNT.labels(method=method, endpoint=endpoint).inc()

    log.info(
        "http_request",
        method=method,
        path=endpoint,
        status_code=status,
        duration_s=round(duration, 4),
        env=ENV_NAME,
    )
    return response


# ── Endpoints ─────────────────────────────────────────────────────────────────
@app.get("/")
async def root():
    return {
        "message": "Hello from DevOps Task!",
        "status": "running",
        "version": APP_VERSION,
    }


@app.get("/health")
async def health():
    if _shutdown:
        return Response(content='{"status":"shutting_down"}', status_code=503,
                        media_type="application/json")
    return {"status": "healthy", "version": APP_VERSION, "env": ENV_NAME}


@app.get("/metrics")
async def metrics():
    data = generate_latest()
    return Response(content=data, media_type=CONTENT_TYPE_LATEST)


# ── Entry point ───────────────────────────────────────────────────────────────
if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=PORT,
        log_level=LOG_LEVEL.lower(),
        access_log=False,  # handled by middleware
    )
