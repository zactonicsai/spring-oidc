"""python-demo WEB — a Flask page that calls the API over the cluster network.

Environment variables (all optional, all injected by the chart / compose / terraform):
  GREETING   -> ConfigMap        API_URL -> ConfigMap, e.g. http://python-demo-api
  APP_NAME, SERVICE_NAME, APP_VERSION -> injected automatically
"""
import json
import logging
import os
import socket
import urllib.error
import urllib.request

from flask import Flask, jsonify, request

from metrics import setup_metrics

app = Flask(__name__)
logging.basicConfig(level=os.getenv("LOG_LEVEL", "info").upper())
log = logging.getLogger("web")

GREETING = os.getenv("GREETING", "Hello from Kubernetes")
API_URL = os.getenv("API_URL", "http://python-demo-api").rstrip("/")
APP_NAME = os.getenv("APP_NAME", "python-demo")
SERVICE_NAME = os.getenv("SERVICE_NAME", "web")
APP_VERSION = os.getenv("APP_VERSION", "dev")
setup_metrics(app, SERVICE_NAME, APP_VERSION)          # GET /metrics for Prometheus


def call_api(path: str, timeout: float = 2.0) -> dict:
    """GET the api service. Any failure is returned as data so the page can explain it."""
    url = f"{API_URL}{path}"
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:  # noqa: S310 (internal URL)
            return {"ok": True, "url": url, "data": json.loads(resp.read().decode())}
    except urllib.error.URLError as exc:
        log.warning("api call failed url=%s err=%s", url, exc)
        return {"ok": False, "url": url, "error": str(exc.reason)}
    except Exception as exc:  # noqa: BLE001
        log.warning("api call failed url=%s err=%s", url, exc)
        return {"ok": False, "url": url, "error": str(exc)}


@app.get("/")
def home():
    name = request.args.get("name", "friend")
    api = call_api(f"/api/hello?name={name}")
    api_line = (
        f"<p><b>API says:</b> {api['data']['message']} <i>(answered by pod {api['data']['pod']})</i></p>"
        if api["ok"]
        else f"<p style='color:#b00'><b>API call failed:</b> {api['error']}<br><small>url: {api['url']}</small></p>"
    )
    return f"""<!doctype html>
<html><head><title>{APP_NAME} web</title></head>
<body style="font-family:Arial,sans-serif;margin:40px;max-width:720px">
  <h1>{GREETING}</h1>
  <p>This page is served by the <b>{SERVICE_NAME}</b> container of <b>{APP_NAME}</b> v{APP_VERSION}.</p>
  <p><b>Pod:</b> {socket.gethostname()} &nbsp; (refresh a few times — with 2+ replicas the pod name changes)</p>
  {api_line}
  <p>Try: <code>/?name=YourName</code>, <code>/config</code>, <code>/health</code>, <code>/api-config</code></p>
</body></html>"""


@app.get("/config")
def config():
    """Non-secret settings only. The web service has no secrets by design."""
    return jsonify(pod=socket.gethostname(), greeting=GREETING, api_url=API_URL,
                   log_level=os.getenv("LOG_LEVEL", "info"), version=APP_VERSION)


@app.get("/api-config")
def api_config():
    """Ask the API for ITS config (the secret comes back masked) — shows the network path web -> api."""
    return jsonify(call_api("/api/config"))


@app.get("/health")
def health():
    return jsonify(status="ok", service=SERVICE_NAME)


if __name__ == "__main__":  # local dev only; the container runs gunicorn (see Dockerfile)
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")))
