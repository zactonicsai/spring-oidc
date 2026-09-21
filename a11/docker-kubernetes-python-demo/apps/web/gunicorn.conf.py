# gunicorn hooks needed for Prometheus multiprocess metrics (see metrics.py)
import os

from prometheus_client import multiprocess


def on_starting(server):
    d = os.getenv("PROMETHEUS_MULTIPROC_DIR")
    if d:
        os.makedirs(d, exist_ok=True)
        for f in os.listdir(d):                       # stale files from a previous run
            os.remove(os.path.join(d, f))


def child_exit(server, worker):                        # forget a dead worker's series
    if os.getenv("PROMETHEUS_MULTIPROC_DIR"):
        multiprocess.mark_process_dead(worker.pid)
