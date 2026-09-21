# Prometheus + Grafana: Monitoring Above the Kubernetes Layer

*Installs the kube-prometheus-stack (Prometheus Operator, Prometheus, Alertmanager, Grafana,
node-exporter, kube-state-metrics, ~30 dashboards, ~150 alerts) and — the part this tutorial is
really about — adds the **service-level** metrics, dashboards and alerts that tell you whether
Keycloak, the python-demo services and the devbox are actually *working for users*, which no
CPU graph can. Current as of September 2026 (kube-prometheus-stack chart ~80, Prometheus 3,
Grafana 12, Keycloak 26.7 metrics).*

| Part | What you learn |
|---|---|
| [1](#part-1--step-by-step) | Deploy, open Grafana, see the dashboards, fire an alert on purpose |
| [2](#part-2--what-the-stack-is) | Operator, ServiceMonitor, PrometheusRule, Alertmanager, Grafana sidecars |
| [3](#part-3--key-monitoring-above-kubernetes-metrics) | **What to watch beyond CPU/memory** — golden signals, Keycloak, JVM, DB, apps, SLOs |
| [4](#part-4--what-this-project-adds) | The ServiceMonitors, rules, dashboard, network policies, app instrumentation |
| [5](#part-5--best-practices) | Labels, cardinality, retention, alert design, on-call routing, security |
| [6](#part-6--gotchas) | Selectors, network policies, multiprocess Python, control-plane targets, CRDs |
| [7](#part-7--pros-and-cons) | Self-hosted stack vs Azure Managed Prometheus/Grafana vs SaaS |

---

## Part 1 — Step by step

```bash
./scripts/monitoring.sh deploy                     # ≈ 3 min on kind; installs the chart, then our monitors/rules/dashboard/policies
./scripts/monitoring.sh password                   # Grafana admin password (generated, stored in a Secret)
./scripts/monitoring.sh open                       # kind: Grafana :3000, Prometheus :9090, Alertmanager :9093  (AKS: `status` prints the Grafana IP)
./scripts/monitoring.sh targets                    # every scrape target and whether it is up
```

In Grafana: **Dashboards → python-demo · Keycloak · devbox — service health** (ours), plus the
built-in *Kubernetes / Compute Resources / Namespace (Pods)* and *Node Exporter / Nodes*.
In Prometheus (`:9090`) try:

```promql
sum(rate(keycloak_user_events_total{event="login"}[5m]))                     # logins per second
sum(rate(flask_http_request_total{namespace="python-demo"}[5m])) by (job)     # app traffic by service
histogram_quantile(0.95, sum(rate(flask_http_request_duration_seconds_bucket[5m])) by (le, job))
```

Make things happen and watch:

```bash
./scripts/07-scale.sh load 60                      # app traffic + latency → the app panels move, HPA scales
# login errors: open $(./scripts/keycloak.sh url)/realms/demo/account and enter a wrong password 5+ times
#   → keycloak_user_events_total{event="login_error"} rises; KeycloakHighLoginFailureRate fires after 10 min
#   (the password grant is disabled on these clients on purpose, so curl can't fake logins — that is a feature)
kubectl -n keycloak scale deploy keycloak --replicas=1   # KeycloakBelowMinReplicas fires after 5 min (HPA will restore it)
```

Alertmanager (`:9093`) shows firing alerts; `Watchdog` is always firing on purpose (a heartbeat).

---

## Part 2 — What the stack is

| Component | Grocery-store version | Job |
|---|---|---|
| **Prometheus** | the clipboard inspector who walks every aisle every 30 s | pulls (`scrapes`) `/metrics` text from targets, stores time series, evaluates rules |
| **Prometheus Operator** | the inspector's manager | turns Kubernetes objects (`ServiceMonitor`, `PodMonitor`, `PrometheusRule`) into Prometheus config, so *you* never edit `prometheus.yml` |
| **ServiceMonitor** | "also inspect the bakery counter, port 9000, path /metrics" | selects Services by label + namespace and names the port/path to scrape |
| **PrometheusRule** | the checklist of things that are *wrong* | alerting rules (`expr` … `for` … `labels.severity`) and recording rules |
| **Alertmanager** | the pager | groups, deduplicates, silences, routes alerts to Slack/Teams/PagerDuty/email |
| **Grafana** | the wall of screens | dashboards on top of Prometheus (and Loki/Tempo later); sidecars auto-load dashboards from ConfigMaps |
| **node-exporter** | thermometers on every wall | host metrics (CPU, disk, network, filesystem) per node |
| **kube-state-metrics** | the inventory count | *state* of Kubernetes objects: desired vs ready replicas, PVC phases, job status |
| **cAdvisor** (in kubelet) | meters on each cart | per-container CPU/memory/network — the usual "Kubernetes metrics" |

Data flow: pod exposes `/metrics` → Service has a named port → ServiceMonitor selects the Service
→ Operator writes the scrape config → Prometheus scrapes → rules evaluate → Alertmanager pages →
Grafana draws.

---

## Part 3 — Key monitoring above Kubernetes metrics

CPU, memory and restarts (what kube-prometheus-stack gives you by default) tell you the
*machines* are fine. Users don't care about machines. The monitoring that matters sits one to
three layers higher:

### 3.1 The four golden signals, per service (RED)

| Signal | Question | Metric in this project |
|---|---|---|
| **Rate** | how much work is coming in? | `rate(flask_http_request_total[5m])`, `rate(http_server_requests_seconds_count{namespace="keycloak"}[5m])` |
| **Errors** | how much of it fails? | `flask_http_request_total{status=~"5.."}`, `keycloak_user_events_total{event="login_error"}` |
| **Duration** | how slow is it? (p50/p95/p99, never the average) | `flask_http_request_duration_seconds_bucket`, `http_server_requests_seconds_bucket` |
| **Saturation** | how close to a limit? | HPA at `maxReplicas`, JVM heap %, DB pool in use, PVC % full, CPU throttling |

Rule of thumb: **alert on symptoms (errors, latency, availability), page on user impact, graph
causes (CPU, GC, pool)**.

### 3.2 Keycloak — an identity service has its own vital signs

| Watch | Why | Metric (Keycloak 26 with `KC_METRICS_ENABLED`, event metrics on) |
|---|---|---|
| **Login success / failure rate** | the one thing users notice; failure spikes = outage, brute force, broken client, expired secret | `keycloak_user_events_total{event="login"}`, `{event="login_error"}` (tags `realm`, `client_id`) |
| Token issuance and refresh rates | APIs go dark when tokens can't be issued | events `code_to_token`, `refresh_token`, `client_login`, `refresh_token_error` |
| **Availability ≥ 2 replicas + cache cluster size** | one replica = sessions lost on restart | `up{container="keycloak"}`, `vendor_cluster_size` |
| Request latency by endpoint | slow token endpoint = every app slow | `http_server_requests_seconds` histogram (`KC_HTTP_METRICS_HISTOGRAMS_ENABLED`) |
| **JVM heap, GC pause, threads** | heap at limit → latency spikes → OOMKilled | `jvm_memory_used_bytes{area="heap"}`, `jvm_gc_pause_seconds`, `jvm_threads_live_threads` |
| **DB connection pool** | pool exhausted = logins hang while pods look healthy | `agroal_active_count`, `agroal_available_count`, `agroal_blocking_time_total` |
| Password hashing time | tells you sizing headroom (hashing is the CPU hog) | `keycloak_credentials_password_hashing_validations_total` |
| Brute-force lockouts, admin events | security signals | admin events → logs; export with the events listener or Loki |
| Certificate/key rotation | tokens fail everywhere when a key expires | check JWKS `kid` changes; external probes with `blackbox_exporter` on `/realms/demo/.well-known/openid-configuration` |

### 3.3 The database behind Keycloak (Postgres)

Connections used vs `max_connections`, replication lag (when you have a replica), transaction
rate, cache hit ratio, **disk free on the PVC** (`kubelet_volume_stats_available_bytes`), backup age.
Add `prometheus-postgres-exporter` (or Azure Database for PostgreSQL insights) for the first four;
the PVC alert is already in `rules.yaml`.

### 3.4 Your own services

* Instrument with a client library (`prometheus-flask-exporter` here; Micrometer for Java/Spring;
  `prometheus-cpp`/OpenTelemetry for C++; `promhttp` for Go). Expose `/metrics`; exclude health/metrics
  endpoints from request metrics.
* Track **business events** as counters (orders placed, logins, jobs processed) — the fastest way
  to detect "nothing errors but nothing works".
* Export a build-info gauge (`app_info{version=…}`) so a bad deploy correlates with a version label.
* External **blackbox probes** (uptime from outside the cluster) for every public entry point.

### 3.5 Platform-level things Kubernetes metrics don't show

* Certificate expiry (cert-manager metrics, blackbox `probe_ssl_earliest_cert_expiry`).
* Persistent volume fullness and IOPS throttling (Azure disks throttle!).
* HPA at max / cluster autoscaler unable to add nodes (`kube_horizontalpodautoscaler_status_desired_replicas` vs `spec_max_replicas`).
* NetworkPolicy drops (Cilium/Hubble flow metrics) — "it's not a bug, it's blocked".
* Backup success/age, image pull errors, quota usage, cost per namespace.
* **Logs and traces**: metrics tell you *that*, logs/traces tell you *why*. Add Loki (logs) and
  Tempo/OpenTelemetry (traces) next; Grafana already has the data-source hooks.

### 3.6 SLOs make it actionable

Define one or two SLOs per user-facing service: e.g. *99.5 % of logins succeed and complete under
1 s over 30 days*. Alert on **burn rate** (error budget consumed too fast), not on every blip.
The two rules `AppHighErrorRate` and `KeycloakHighLoginFailureRate` are simple stand-ins; use the
`sloth` or `pyrra` tools to generate proper multi-window burn-rate alerts.

---

## Part 4 — What this project adds

| File | What it does |
|---|---|
| `k8s/monitoring/values.yaml` | chart values: **discover all ServiceMonitors/Rules** (`*NilUsesHelmValues: false`), disable unreachable control-plane scrapes, 7 d retention, Grafana admin from an existing Secret, dashboard sidecar, Alertmanager route skeleton |
| `k8s/monitoring/values-kind.yaml` | kind/Docker Desktop overrides (no host root mount for node-exporter, smaller resources) |
| `k8s/monitoring/servicemonitors.yaml` | scrape Keycloak on port `management` (9000, on the internal headless Service only) and python-demo web/api on port `http` (`/metrics`) |
| `k8s/monitoring/rules.yaml` | alerts: `KeycloakBelowMinReplicas`, `KeycloakHighLoginFailureRate`, `KeycloakHighLatencyP95`, `KeycloakJvmHeapHigh`, `KeycloakDatabaseDown`, `AppHighErrorRate`, `AppHighLatencyP95`, `AppNoTraffic`, `DevboxNotReady`, `PersistentVolumeAlmostFull` |
| `k8s/monitoring/dashboard-configmap.yaml` | an 11-panel Grafana dashboard (logins, login errors, Keycloak p95, JVM heap, DB pool, cache members, app rate/error %/p95, pod CPU/memory) loaded by the sidecar |
| `k8s/monitoring/netpol-allow-scrape.yaml` | lets the `monitoring` namespace reach python-demo pods on 8080 (the namespace is default-deny); the keycloak policy allows monitoring → 9000 |
| `apps/*/metrics.py`, `gunicorn.conf.py` | `prometheus-flask-exporter` in **multiprocess** mode (gunicorn has 2 workers; `PROMETHEUS_MULTIPROC_DIR=/tmp/prometheus`), `app_info` gauge, health/metrics excluded |
| `k8s/keycloak/20-keycloak.yaml` | `KC_METRICS_ENABLED`, `KC_HTTP_METRICS_HISTOGRAMS_ENABLED`, `KC_EVENT_METRICS_USER_ENABLED`, `KC_EVENT_METRICS_USER_TAGS=realm,clientId`; port 9000 on the headless Service |
| `scripts/monitoring.sh` | `deploy · status · open · password · targets · destroy` |

---

## Part 5 — Best practices

* **Labels are the schema**: use `job`/`namespace` from the operator, keep app labels low-cardinality
  (endpoint *name*, not URL with IDs; status class, not user id). One high-cardinality label can
  take Prometheus down.
* **Histograms, not averages**, for latency; pick buckets around your SLO (`0.1, 0.25, 0.5, 1, 2.5 s`).
* **Retention**: 7–15 days locally; ship to long-term storage (Thanos, Mimir, Azure Managed
  Prometheus) for months. Persist Prometheus on a PVC in anything but a demo (`storageSpec` in values).
* **Alert design**: `for:` windows to avoid flapping, `severity` labels (`critical` pages,
  `warning` tickets, `info` dashboards), runbook URL annotations, and a *silence* culture. Route
  through Alertmanager receivers (Slack/Teams/PagerDuty); keep `Watchdog` wired to a dead-man's switch.
* **Scrape only what you use**: every ServiceMonitor costs storage; drop noisy series with
  `metricRelabelings`.
* **Secure the stack**: Grafana behind Keycloak (generic OAuth — realm *demo*, group `/admins` →
  Grafana Admin), no anonymous access, Prometheus/Alertmanager not exposed publicly (the script only
  exposes Grafana), NetworkPolicies for scrape paths, read-only dashboards from git (ConfigMaps).
* **Version and pin**: `KPS_VERSION=<chart version> ./scripts/monitoring.sh deploy` in production;
  read the chart's upgrade notes — CRDs must be updated manually on major bumps.
* **Test alerts**: `promtool test rules`, `amtool`, and break things on purpose (Part 1).
* **Dashboards as code**: keep JSON in git (as here) or use Grafana's Terraform provider/Grafonnet.

---

## Part 6 — Gotchas

| Symptom | Cause | Fix |
|---|---|---|
| Your ServiceMonitor/PrometheusRule is ignored | the chart's default selectors only match objects with the release label | `serviceMonitorSelectorNilUsesHelmValues: false` (+ pod/rule/probe) — set in `values.yaml` |
| Targets `DOWN`, `context deadline exceeded` | NetworkPolicy blocks Prometheus | `netpol-allow-scrape.yaml` (python-demo) and the monitoring rule in the keycloak policy |
| Keycloak target `DOWN` on port 9000 | metrics not enabled / port not on the Service | `KC_METRICS_ENABLED=true`; port `management` on `keycloak-headless` |
| `keycloak_user_events_total` never appears | user event metrics are opt-in | `KC_EVENT_METRICS_USER_ENABLED=true`; a login must happen first |
| Python counters jump up and down | several gunicorn workers each report their own registry | multiprocess mode: `PROMETHEUS_MULTIPROC_DIR` + `GunicornInternalPrometheusMetrics` + `child_exit` hook (done) |
| `/metrics` counts health checks | probes every 5–10 s dominate the rate | `excluded_paths` for `/health` and `/metrics` |
| Permanent `KubeControllerManagerDown` / `KubeSchedulerDown` / `etcd` alerts | managed/kind clusters don't expose those | disabled in `values.yaml` |
| node-exporter `CrashLoopBackOff` on Docker Desktop | `/` host mount not allowed | `hostRootFsMount.enabled: false` (`values-kind.yaml`) |
| Prometheus `OOMKilled` | cardinality or retention | check `topk(20, count by (__name__)({__name__=~".+"}))`; drop labels; raise the limit |
| `helm uninstall` leaves CRDs behind | by design | `monitoring.sh destroy` deletes them; be careful, it deletes *all* ServiceMonitors |
| Grafana dashboard doesn't show up | ConfigMap lacks the label or wrong namespace search | label `grafana_dashboard: "1"`; `searchNamespace: ALL` |
| `histogram_quantile` returns `NaN` | no `_bucket` samples yet, or histograms disabled | generate traffic; `KC_HTTP_METRICS_HISTOGRAMS_ENABLED=true` |
| Grafana LoadBalancer public but no login | it always requires login; the password is in the Secret | `./scripts/monitoring.sh password`; put it behind Keycloak next |

---

## Part 7 — Pros and cons

| | kube-prometheus-stack (this) | Azure Monitor managed Prometheus + managed Grafana | SaaS (Datadog, Grafana Cloud, New Relic) |
|---|---|---|---|
| Runs where | in your cluster | Azure-managed, scraped by an agent in the cluster | vendor cloud, agent in the cluster |
| Cost | node resources only; storage | per-sample ingestion + Grafana instance | per host/ingestion — the most expensive |
| Long-term storage | you add Thanos/Mimir | built in (18 months) | built in |
| Portability | works on kind, AKS, anywhere | Azure only (Prometheus-compatible though) | vendor |
| Alerting | Alertmanager (you route it) | Azure alert rules + action groups | vendor |
| Upgrades/ops | yours (chart bumps, CRDs) | Microsoft's | vendor's |
| Best for | learning, portability, control | AKS production with little ops capacity | teams that want everything (logs, traces, APM) as one service |

The layered answer: **instrument once** (Prometheus-format `/metrics` and OpenTelemetry), keep
the dashboards and rules in git as here — then the backend (self-hosted, Azure managed, SaaS) is a
deployment choice you can change later.
