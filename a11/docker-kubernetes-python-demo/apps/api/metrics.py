"""Prometheus metrics for the Flask apps (shared by web and api).

Exposes GET /metrics with the RED signals per endpoint:
  flask_http_request_total{method,status,endpoint}          rate + errors
  flask_http_request_duration_seconds_bucket{...}           latency histogram (p50/p95/p99)
  app_info{app,service,version}                             which build is running
gunicorn runs several worker processes; each has its own counters, so metrics are aggregated
through the multiprocess registry in PROMETHEUS_MULTIPROC_DIR (set in the Dockerfile, /tmp is
a writable emptyDir/tmpfs). Without that variable (plain `flask run`) a single-process registry is used.
"""
import os

from prometheus_client import Gauge


EXCLUDED = ["^/health$", "^/metrics$"]     # probes and scrapes are noise in request metrics


def setup_metrics(app, service_name: str, version: str):
    if os.getenv("PROMETHEUS_MULTIPROC_DIR"):
        from prometheus_flask_exporter.multiprocess import GunicornInternalPrometheusMetrics

        os.makedirs(os.environ["PROMETHEUS_MULTIPROC_DIR"], exist_ok=True)
        metrics = GunicornInternalPrometheusMetrics(app, group_by="endpoint", path="/metrics", excluded_paths=EXCLUDED)
    else:
        from prometheus_flask_exporter import PrometheusMetrics

        metrics = PrometheusMetrics(app, group_by="endpoint", path="/metrics", excluded_paths=EXCLUDED)
    metrics.info("app_info", "Application build information",
                 app=os.getenv("APP_NAME", "python-demo"), service=service_name, version=version)
    return metrics


# a gauge every service can use for "what is my current state" style numbers
in_flight = Gauge("app_requests_in_flight", "Requests currently being handled", multiprocess_mode="livesum")
