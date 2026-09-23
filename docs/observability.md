# Observability Plan

> **Part 5 — Stretch Goal**

## Purpose of this document

This document explains how observability could be added to the Notes API in a production environment.

The main assignment focuses on Docker, Helm/Kubernetes, GitHub Actions CI, and ArgoCD GitOps. Full Prometheus/Grafana implementation is not required for the core assignment, so this document records the observability hooks included in the project and the approach I would use to monitor the application in production.

It also clearly separates what is implemented in this assignment from what is proposed as a future production enhancement.

## Current state

The Notes API Deployment includes standard Prometheus scrape annotations:

- `prometheus.io/scrape: "true"`
- `prometheus.io/port: "8000"`
- `prometheus.io/path: "/metrics"`

These annotations indicate how a Prometheus-based monitoring system could discover the application.

The `/metrics` endpoint itself is not implemented because the provided application code under `app/` was kept unchanged, as required by the assignment.

Therefore, this document describes the intended Prometheus integration rather than claiming a complete Prometheus/Grafana implementation.

## What a real `/metrics` endpoint could expose

For a FastAPI application, a library such as `prometheus-fastapi-instrumentator` could be used to expose application and process metrics.

Examples include:

- HTTP request count
- HTTP request duration
- Request and response status information
- Process memory usage
- Open file descriptors
- Other application/process-level metrics supported by the instrumentation library

The exact metric names and labels would depend on the instrumentation configuration and library version.

## ServiceMonitor

If the Prometheus Operator were installed, a `ServiceMonitor` could be used to discover and scrape the Notes API Kubernetes Service.

Example:

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