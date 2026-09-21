"""python-demo API — a tiny Flask JSON service.

Everything it needs arrives as environment variables:
  GREETING, LOG_LEVEL      -> from the ConfigMap  (services[].config in app.config.yaml)
  API_TOKEN                -> from the Secret     (services[].secrets in app.config.yaml)
  APP_NAME, SERVICE_NAME, APP_VERSION -> injected automatically by the Helm chart / compose / terraform
"""
import logging
import os
import socket
import time

from flask import Flask, jsonify, request

from metrics import setup_metrics

app = Flask(__name__)
logging.basicConfig(level=os.getenv("LOG_LEVEL", "info").upper())
log = logging.getLogger("api")

GREETING = os.getenv("GREETING", "Hello")
APP_NAME = os.getenv("APP_NAME", "python-demo")
SERVICE_NAME = os.getenv("SERVICE_NAME", "api")
APP_VERSION = os.getenv("APP_VERSION", "dev")
setup_metrics(app, SERVICE_NAME, APP_VERSION)          # GET /metrics for Prometheus


def masked_secret(name: str) -> str:
    """Never print a secret. Show only that it exists and its last 2 characters."""
    value = os.getenv(name)
    if not value:
        return "(not set)"
    return "*" * max(len(value) - 2, 4) + value[-2:]


@app.get("/")
def root():
    return jsonify(service=SERVICE_NAME, app=APP_NAME, version=APP_VERSION,
                   message="Python API is running", pod=socket.gethostname())


@app.get("/api/hello")
def hello():
    name = request.args.get("name", "World")
    log.info("hello GET name=%s", name)
    return jsonify(message=f"{GREETING}, {name}!", pod=socket.gethostname())


@app.post("/api/hello")
def hello_post():
    body = request.get_json(silent=True) or {}
    name = body.get("name", "World")
    log.info("hello POST name=%s", name)
    return jsonify(message=f"{GREETING}, {name}!", pod=socket.gethostname())


@app.get("/api/config")
def config():
    """Proves ConfigMap + Secret injection without leaking the secret value."""
    return jsonify(
        pod=socket.gethostname(),
        greeting=GREETING,
        log_level=os.getenv("LOG_LEVEL", "info"),
        api_token=masked_secret("API_TOKEN"),
        version=APP_VERSION,
    )


@app.get("/api/work")
def work():
    """Burn CPU for ?ms=<milliseconds> (max 5000). Used to trigger the HorizontalPodAutoscaler."""
    ms = min(int(request.args.get("ms", "200")), 5000)
    end = time.perf_counter() + ms / 1000.0
    n = 0
    while time.perf_counter() < end:  # busy loop = real CPU usage the HPA can see
        n += 1
    return jsonify(pod=socket.gethostname(), busy_ms=ms, loops=n)


@app.get("/health")
def health():
    return jsonify(status="ok", service=SERVICE_NAME)


if __name__ == "__main__":  # local dev only; the container runs gunicorn (see Dockerfile)
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")))
