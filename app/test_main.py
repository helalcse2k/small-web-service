"""
Unit tests for the FastAPI web service endpoints.
"""

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from main import app


@pytest_asyncio.fixture
async def client():
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as ac:
        yield ac


@pytest.mark.asyncio
async def test_root_returns_hello(client):
    resp = await client.get("/")
    assert resp.status_code == 200
    body = resp.json()
    assert body["message"] == "Hello from DevOps Task!"
    assert body["status"] == "running"
    assert "version" in body


@pytest.mark.asyncio
async def test_health_returns_healthy(client):
    resp = await client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "healthy"
    assert "version" in body


@pytest.mark.asyncio
async def test_metrics_returns_prometheus_format(client):
    resp = await client.get("/metrics")
    assert resp.status_code == 200
    assert "text/plain" in resp.headers["content-type"]
    text = resp.text
    assert "http_requests_total" in text
    assert "http_request_duration_seconds" in text


@pytest.mark.asyncio
async def test_root_increments_request_counter(client):
    # Hit root twice to ensure counter tracks
    await client.get("/")
    await client.get("/")
    metrics_resp = await client.get("/metrics")
    assert 'endpoint="/"' in metrics_resp.text


@pytest.mark.asyncio
async def test_unknown_path_returns_404(client):
    resp = await client.get("/does-not-exist")
    assert resp.status_code == 404
