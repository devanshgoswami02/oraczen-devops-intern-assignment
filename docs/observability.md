# Observability Plan (Part 5 — Stretch)

## Current state

The pod template carries standard Prometheus scrape annotations:

- `prometheus.io/scrape: "true"`
- `prometheus.io/port: "8000"`
- `prometheus.io/path: "/metrics"`

The `/metrics` endpoint itself is not implemented because the provided
application code under `app/` is not being modified. This section therefore
documents the intended Prometheus integration rather than implementing it
end-to-end.

## What a real `/metrics` endpoint would expose

Using `prometheus-fastapi-instrumentator`, the application could expose:

- `http_requests_total` — request count by path, method, and status
- `http_request_duration_seconds` — request duration histogram
- Default process metrics such as memory usage and open file descriptors

## ServiceMonitor

If the Prometheus Operator were installed, a `ServiceMonitor` could be
used to discover and scrape the Notes API:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: notes-api
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: notes-api
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
