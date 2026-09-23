# Oraczen DevOps Intern Assignment — Detailed Write-up

## 1. Introduction

This project was completed as part of the **Oraczen DevOps Intern assignment**.

The assignment provided a FastAPI + PostgreSQL Notes API and asked me to build the DevOps infrastructure around it.

I kept the application logic unchanged and focused on:

- Containerizing the application with Docker
- Creating a Helm chart
- Deploying PostgreSQL as a Helm dependency
- Managing Kubernetes configuration and Secrets
- Adding health probes and resource limits
- Adding Kubernetes security settings
- Building a GitHub Actions CI pipeline
- Adding Trivy security scanning
- Managing Dev and Prod deployments with ArgoCD
- Using GitOps as the deployment model
- Adding HPA as stretch work
- Documenting observability and production-oriented secrets management

The implementation was tested locally using **kind** rather than a real AWS EKS cluster because the assignment did not require a cloud deployment.

---

# 2. Technologies Used

| Area | Technology |
|---|---|
| Application | FastAPI + PostgreSQL |
| Containerization | Docker |
| Kubernetes | kind |
| Package Management | Helm 3 |
| CI | GitHub Actions |
| Python Linting | Ruff |
| Security Scanning | Trivy |
| GitOps | ArgoCD |
| Autoscaling | Kubernetes HPA |
| Environment | Windows + WSL2 + Docker Desktop |
| Source Control | Git + GitHub |

---

# 3. Overall Architecture

The overall implementation follows this flow:

```text
                         GitHub Repository
                               |
                 +-------------+-------------+
                 |                           |
                 v                           v
        GitHub Actions CI              ArgoCD
                 |                           |
        +--------+--------+           Watches Git
        |        |        |                 |
      Ruff    Docker    Trivy               v
                Build     |          Helm Chart
                  |       |                 |
                  +-------+                 v
                    |                 Kubernetes
                    |                     |
                    |             +-------+-------+
                    |             |               |
                    |             v               v
                    |         Notes API       PostgreSQL
                    |             |
                    |             v
                    |            HPA
                    |
                    v
              CI Security Gate
```

For ArgoCD, the two environments are:

```text
GitHub
  |
  v
ArgoCD
  |
  +--------------------------+
  |                          |
  v                          v
notes-api-dev           notes-api-prod
  |                          |
Auto Sync                 Manual Sync
Prune                     Manual approval
Self Heal
```

Git is the source of truth for the ArgoCD-managed application resources.

---

# Part 1 — Containerize the App

## 1.1 What I Built

I created a multi-stage Dockerfile for the provided FastAPI application.

The Dockerfile uses:

- Python 3.12 slim
- A separate builder stage
- A runtime stage
- Non-root user
- Selective application file copying
- `PYTHONUNBUFFERED`
- Docker healthcheck
- Port 8000
- Uvicorn

The application code itself was not modified.

---

## 1.2 Dockerfile Design

The builder stage installs the Python dependencies:

```dockerfile
FROM python:3.12-slim AS builder

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir --user -r requirements.txt
```

The runtime stage uses another slim Python image:

```dockerfile
FROM python:3.12-slim
```

A non-root user is created:

```dockerfile
RUN useradd --create-home --uid 1000 appuser
```

The installed Python packages are copied from the builder:

```dockerfile
COPY --from=builder /root/.local /home/appuser/.local
```

Only the required application files are copied:

```dockerfile
COPY main.py database.py models.py schemas.py ./
```

The application runs as:

```dockerfile
USER appuser
```

The container also contains a healthcheck:

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/healthz')" || exit 1
```

---

## 1.3 Commands Used

Build the application image:

```bash
docker build -t notes-api:local -f app/Dockerfile app
```

Build the verification image:

```bash
docker build -t notes-api:verification -f app/Dockerfile app
```

Inspect the image:

```bash
docker image inspect notes-api:verification \
  --format 'User={{.Config.User}} Entrypoint={{json .Config.Entrypoint}} Cmd={{json .Config.Cmd}}'
```

The inspection showed:

```text
User=appuser
```

which verified that the container does not run as root.

---

## 1.4 Verification

I tested the image locally with PostgreSQL.

I verified:

- Container starts successfully
- Application runs as `appuser`
- Port 8000 is available
- `/healthz` returns successfully
- `/readyz` returns successfully
- API can communicate with PostgreSQL

The final Docker image was approximately:

```text
274 MB
```

---

## 1.5 Evidence

![Docker Desktop image](screenshots/part-1-docker/01-01-docker-desktop-image.png)

The screenshot shows the locally built Notes API images in Docker Desktop.

---

## 1.6 Assignment Requirements Covered

The Docker implementation covers:

- Multi-stage build
- Slim Python base image
- Non-root runtime
- `.dockerignore`
- Healthcheck
- Reasonably controlled runtime image
- Application listening on port 8000

---

## 1.7 Trade-offs / What I Would Improve

The image is functional and reasonably controlled, but it can still be reduced further.

For a real production environment I would consider:

- More aggressive dependency minimization
- Dependency vulnerability management
- SBOM generation
- Image signing
- Image-size limits
- Automated dependency updates

I did not modify the starter application's dependency versions only to make the security scan pass because the assignment focused on building the infrastructure around the provided application.

---

# Part 2 — Helm Chart with PostgreSQL

## 2.1 What I Built

I created the Helm chart under:

```text
helm/notes-api/
```

The chart manages:

- Notes API Deployment
- Kubernetes Service
- ConfigMap
- ServiceAccount
- PostgreSQL dependency
- Liveness probe
- Readiness probe
- Resource requests and limits
- Security context
- Optional HPA

The chart contains separate environment values:

```text
values.yaml
values-dev.yaml
values-prod.yaml
```

---

## 2.2 Helm Chart Structure

```text
helm/notes-api/
├── Chart.yaml
├── Chart.lock
├── values.yaml
├── values-dev.yaml
├── values-prod.yaml
├── charts/
│   └── postgresql-18.11.6.tgz
└── templates/
    ├── _helpers.tpl
    ├── configmap.yaml
    ├── deployment.yaml
    ├── hpa.yaml
    ├── NOTES.txt
    ├── service.yaml
    └── serviceaccount.yaml
```

---

# 2.3 PostgreSQL Dependency

PostgreSQL is managed as a Helm dependency using the Bitnami PostgreSQL chart.

The dependency is declared in `Chart.yaml`.

I built the dependency using:

```bash
helm dependency build helm/notes-api
```

The PostgreSQL chart was downloaded and stored locally as:

```text
helm/notes-api/charts/postgresql-18.11.6.tgz
```

---

## 2.4 Helm Validation

I checked the chart using:

```bash
helm lint helm/notes-api
```

I also rendered the Development environment:

```bash
helm template notes-api helm/notes-api \
  -f helm/notes-api/values-dev.yaml
```

and the Production environment:

```bash
helm template notes-api helm/notes-api \
  -f helm/notes-api/values-prod.yaml
```

Both Dev and Prod rendering completed successfully.

---

# 2.5 Secret Wiring

One of the important requirements of this assignment was the PostgreSQL Secret wiring.

The application should not have the PostgreSQL password duplicated as a plaintext value in its own values file.

The Notes API Deployment obtains the password through a Kubernetes Secret:

```yaml
env:
  - name: POSTGRES_PASSWORD
    valueFrom:
      secretKeyRef:
        name: {{ include "notes-api.postgresFullname" . }}
        key: password
```

The other database configuration is supplied separately through the ConfigMap.

The application therefore receives:

```text
POSTGRES_HOST
POSTGRES_PORT
POSTGRES_USER
POSTGRES_DB
```

from normal configuration and:

```text
POSTGRES_PASSWORD
```

from the Kubernetes Secret.

---

# 2.6 Assignment Question — PostgreSQL Secret Wiring

## Question

**How does the application get the PostgreSQL password without storing the password directly in the application's values?**

## Answer

The PostgreSQL password is stored in the Kubernetes Secret associated with the PostgreSQL Helm dependency.

The Notes API Deployment uses:

```yaml
secretKeyRef
```

to read the `password` key from that Secret.

For example:

```yaml
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: ...
      key: password
```

Therefore, the password is not written directly into the Notes API Deployment or the normal application values file.

For a real AWS deployment, I would replace this local Secret approach with an external secret solution such as:

```text
AWS Secrets Manager
        |
        v
External Secrets Operator
        |
        v
Kubernetes Secret
        |
        v
Notes API
```

The assignment's database.py also separates the `POSTGRES_*` environment variables because connection information can come from normal configuration while the password comes from the Secret.

---

# 2.7 Health Checks

The Notes API Deployment contains two Kubernetes HTTP probes.

### Liveness

```text
/healthz
```

### Readiness

```text
/readyz
```

The liveness probe checks whether the container is alive.

The readiness probe checks whether the application is ready to receive traffic.

---

# 2.8 Kubernetes Security

The container was hardened using:

```yaml
runAsNonRoot: true
runAsUser: 1000
runAsGroup: 1000
```

The container also uses:

```yaml
allowPrivilegeEscalation: false
```

Linux capabilities are dropped:

```yaml
capabilities:
  drop:
    - ALL
```

The root filesystem is read-only:

```yaml
readOnlyRootFilesystem: true
```

CPU and memory requests/limits are also configured.

These settings improved the Kubernetes security posture and helped the configuration scan pass.

---

# 2.9 Development vs Production

## Development

Development uses:

```text
1 replica initially
```

Smaller resource values are used:

```yaml
requests:
  cpu: 50m
  memory: 64Mi
```

PostgreSQL persistence is disabled for local development:

```yaml
postgresql:
  primary:
    persistence:
      enabled: false
```

HPA is enabled in Dev.

---

## Production

Production uses:

```text
2 API replicas
```

Higher resource requests and limits are used:

```yaml
requests:
  cpu: 200m
  memory: 256Mi

limits:
  cpu: 500m
  memory: 512Mi
```

PostgreSQL persistence is enabled:

```yaml
postgresql:
  primary:
    persistence:
      enabled: true
      size: 5Gi
```

Production also reuses the existing PostgreSQL Secret:

```yaml
postgresql:
  auth:
    existingSecret: notes-api-prod-postgresql
```

---

# 2.10 Commands Used

Build dependencies:

```bash
helm dependency build helm/notes-api
```

Lint:

```bash
helm lint helm/notes-api
```

Render Dev:

```bash
helm template notes-api helm/notes-api \
  -f helm/notes-api/values-dev.yaml
```

Render Prod:

```bash
helm template notes-api helm/notes-api \
  -f helm/notes-api/values-prod.yaml
```

Install Dev:

```bash
helm install notes-api-dev helm/notes-api \
  -f helm/notes-api/values-dev.yaml
```

Check Kubernetes resources:

```bash
kubectl get pods
kubectl get svc
kubectl get hpa
```

Port forward:

```bash
kubectl port-forward svc/notes-api-dev-notes-api 8000:8000
```

---

# 2.11 API Verification

I did not only check whether the pods were running.

I also tested the API.

Health:

```bash
kubectl run api-test --rm -it --restart=Never \
  --image=curlimages/curl:8.10.1 \
  -- curl -sS http://notes-api-dev-notes-api:8000/healthz
```

Expected response:

```json
{"status":"ok"}
```

Readiness:

```bash
kubectl run api-test --rm -it --restart=Never \
  --image=curlimages/curl:8.10.1 \
  -- curl -sS http://notes-api-dev-notes-api:8000/readyz
```

Expected response:

```json
{"status":"ready"}
```

I also tested a database write:

```bash
kubectl run api-test --rm -it --restart=Never \
  --image=curlimages/curl:8.10.1 \
  -- curl -sS -X POST \
  http://notes-api-dev-notes-api:8000/notes \
  -H "Content-Type: application/json" \
  -d '{"title":"Verification Test","content":"FastAPI to PostgreSQL connectivity verified"}'
```

Then I tested reading the notes:

```bash
kubectl run api-test --rm -it --restart=Never \
  --image=curlimages/curl:8.10.1 \
  -- curl -sS http://notes-api-dev-notes-api:8000/notes
```

This verified that the API could actually communicate with PostgreSQL.

---

# 2.12 Evidence

![Kubernetes Deployment](screenshots/part-2-kubernetes/02-01-kubernetes-dev-deployment%20%282%29.png)

![API and PostgreSQL evidence](screenshots/part-2-kubernetes/02-02-api-postgres-evidence.png)

The screenshots provide evidence of the Kubernetes deployment and API/PostgreSQL operation.

---

# 2.13 Troubleshooting — PostgreSQL Credential Mismatch

During the production deployment, a newly created API pod failed with:

```text
password authentication failed for user "notes"
```

PostgreSQL itself was running.

The problem was a mismatch between:

```text
Password stored in the initialized PostgreSQL database
```

and:

```text
Password currently referenced by the Kubernetes Secret
```

I compared password hashes between a healthy API pod and the Kubernetes Secret without printing the actual password.

The hashes were different.

This showed that simply having a Kubernetes Secret was not enough because PostgreSQL had already been initialized with a different password.

---

## Resolution

Production was changed to reuse the existing PostgreSQL Secret:

```yaml
postgresql:
  auth:
    existingSecret: notes-api-prod-postgresql
```

The live Secret was then aligned with the password already used by the healthy PostgreSQL database.

The broken API pod was removed so that Kubernetes could recreate it.

The replacement pod became healthy and the rollout completed.

---

# 2.14 ArgoCD Secret Drift Troubleshooting

After fixing the PostgreSQL credential issue, ArgoCD initially showed the production Application as:

```text
OutOfSync
Healthy
```

The application itself was working.

The remaining issue was that the live PostgreSQL Secret was being treated as an extraneous resource because the actual secret value was intentionally kept outside Git.

The Secret was annotated with:

```text
argocd.argoproj.io/compare-options=IgnoreExtraneous
```

After this change, the production Application became:

```text
Synced
Healthy
```

This was an important GitOps lesson: application health and ArgoCD desired-state comparison are related but not exactly the same thing.

---

# 2.15 Trade-offs / What I Would Improve

For a local assignment, using the Bitnami PostgreSQL subchart keeps the setup simple and reproducible.

For a real production environment, I would consider:

- Amazon RDS PostgreSQL
- AWS Secrets Manager
- External Secrets Operator
- Persistent backup strategy
- High availability
- Database monitoring

---

# Part 3 — GitHub Actions CI Pipeline

## 3.1 What I Built

I created:

```text
.github/workflows/ci.yaml
```

The workflow runs for Pull Requests targeting `main`.

The pipeline is:

```text
Pull Request
     |
     v
Python Lint
     |
     v
Docker Build
     |
     v
Trivy Image Scan
     |
     v
Helm Dependency Build
     |
     v
Helm Lint
     |
     v
Helm Render
     |
     v
Trivy Config Scan
```

---

# 3.2 Python Checks

Ruff is used for Python linting.

The workflow runs:

```bash
ruff check app/ --select E,F --ignore E501,F401
```

The purpose is to catch basic Python errors and selected style issues.

---

# 3.3 Docker Build

The image is tagged using the Git commit SHA.

For example:

```text
notes-api:<commit-sha>
```

This makes the image traceable to the exact Git commit that created it.

The image is saved as a GitHub Actions artifact so that the Trivy job can scan the same image.

---

# 3.4 Trivy Image Scan

The image is scanned for:

```text
HIGH
CRITICAL
```

severity vulnerabilities.

The scan is configured as a gate:

```text
exit-code: 1
```

and:

```text
ignore-unfixed: true
```

---

# 3.5 Important CI Result

The starter application's dependency chain contains HIGH severity Starlette vulnerabilities.

The scan detected findings including:

```text
CVE-2024-47874
CVE-2026-48818
CVE-2026-54283
```

Therefore, I am **not claiming that the image security scan is completely green**.

This was intentional from a documentation point of view.

The security gate is doing its job by detecting the vulnerabilities.

I did not modify the starter application dependencies simply to make the scan green because the assignment provided the application and the main task was to build the DevOps infrastructure around it.

---

# 3.6 Helm Validation in CI

The workflow runs:

```bash
helm dependency build helm/notes-api
```

Then:

```bash
helm lint helm/notes-api
```

Then renders the Dev environment:

```bash
helm template notes-api helm/notes-api \
  -f helm/notes-api/values-dev.yaml
```

The rendered Kubernetes manifests are written to a temporary directory.

---

# 3.7 Trivy Kubernetes Configuration Scan

The rendered manifests are scanned with:

```text
Trivy config
```

The first configuration scan identified Kubernetes security issues.

I addressed them using:

```text
runAsNonRoot: true
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities.drop: ALL
resource requests/limits
```

After these changes, the Kubernetes configuration scan passed.

---

# 3.8 Evidence

![GitHub Actions](screenshots/part-3-ci/03-01-github-actions-run.png)

The screenshot shows the GitHub Actions workflow execution.

---

# 3.9 Trade-offs / What I Would Improve

The CI pipeline was intentionally kept focused on the assignment.

For a production pipeline I would additionally consider:

- Publishing images to ECR or GHCR
- Integration tests
- SBOM generation
- Cosign image signing
- Dependency update automation
- Image promotion between environments
- Deployment verification
- Rollback automation

These were not required for the current local implementation.

---

# Part 4 — GitOps with ArgoCD

## 4.1 What I Built

I created two ArgoCD Applications:

```text
notes-api-dev
notes-api-prod
```

Both Applications use the GitHub repository as the source.

The source path is:

```text
helm/notes-api
```

---

# 4.2 Development Sync Policy

Development uses automated synchronization:

```yaml
automated:
  prune: true
  selfHeal: true
```

This means:

- Git changes can be automatically synchronized
- Resources removed from Git can be pruned
- Manual drift can be corrected by ArgoCD

Development therefore behaves as a continuously reconciled environment.

---

# 4.3 Production Sync Policy

Production does not have an `automated` synchronization block.

Production therefore requires a manual synchronization action.

This creates an intentional approval point before production resources are changed.

---

# 4.4 GitOps Workflow

The intended flow is:

```text
Developer
    |
    v
Change Helm / Kubernetes configuration
    |
    v
Git commit
    |
    v
GitHub
    |
    v
ArgoCD detects Git revision
    |
    +----------------------+
    |                      |
    v                      v
Dev                   Prod
Auto Sync             Manual Sync
    |                      |
    v                      v
Kubernetes             Kubernetes
```

Git is the source of truth.

Once ArgoCD was managing the application resources, I avoided manually applying or upgrading the Argo-owned application resources outside the GitOps flow.

---

# 4.5 Assignment Question 1

## Question

**If a developer merges a change to `main`, what happens next?**

## Answer

The sequence is:

```text
Developer changes configuration
          |
          v
Pull Request
          |
          v
GitHub Actions runs
          |
          v
Pull Request is merged to main
          |
          v
Git repository contains new desired state
          |
          v
ArgoCD detects the new Git revision
          |
          +--------------------------+
          |                          |
          v                          v
      Development                Production
       Auto Sync                 Manual Sync
          |                          |
          v                          v
     Kubernetes                  Kubernetes
```

For Dev, ArgoCD automatically synchronizes because automated sync is enabled.

For Prod, ArgoCD detects the Git change, but synchronization requires a manual action.

This gives production an additional review/approval point.

---

# 4.6 Assignment Question 2

## Question

**If a rollout fails after an ArgoCD sync, where would you look first and what commands would you use?**

## Answer

I would first check ArgoCD to determine which resource failed.

Then I would check Kubernetes.

### Step 1 — ArgoCD Application

```bash
kubectl get applications -n argocd
```

I would check:

```text
Sync status
Health status
Failed resources
Events
```

---

### Step 2 — Pods

```bash
kubectl get pods
```

If a pod is failing:

```bash
kubectl describe pod <pod-name>
```

---

### Step 3 — Logs

```bash
kubectl logs <pod-name>
```

If the container restarted:

```bash
kubectl logs <pod-name> --previous
```

---

### Step 4 — Deployment

```bash
kubectl describe deployment <deployment-name>
```

and:

```bash
kubectl rollout status deployment/<deployment-name>
```

---

### Step 5 — Kubernetes Events

```bash
kubectl get events --sort-by=.lastTimestamp
```

These checks can reveal:

- Image pull errors
- Failed health probes
- Scheduling problems
- Insufficient resources
- Secret/configuration problems
- Container crashes
- Service or deployment issues

This was also the approach I used during the actual PostgreSQL authentication troubleshooting.

---

# 4.7 ArgoCD Troubleshooting

During the project I encountered an ArgoCD state where:

```text
Application = Healthy
Sync = OutOfSync
```

The application itself was functioning.

The issue was related to the PostgreSQL Secret being treated as an extraneous resource because its actual value was intentionally maintained outside Git.

The Secret was annotated:

```text
argocd.argoproj.io/compare-options=IgnoreExtraneous
```

After that, the Application became:

```text
notes-api-prod
Synced
Healthy
```

---

# 4.8 Evidence

![ArgoCD Applications](screenshots/part-4-argocd/04-01-argocd-applications.png)

![ArgoCD Dev Resource Tree](screenshots/part-4-argocd/04-02-argocd-dev-resource-tree.png)

![ArgoCD Prod Resource Tree](screenshots/part-4-argocd/04-03-argocd-prod-resource-tree.png)

These screenshots show the Applications and their Kubernetes resource trees.

---

# 4.9 GitOps Trade-offs

The main benefit of this setup is that Git provides a clear desired state.

Advantages:

- Changes are version controlled
- Configuration changes can be reviewed
- ArgoCD continuously compares desired and live state
- Dev can self-heal
- Prod can require manual synchronization
- Rollbacks can use Git history

Trade-off:

GitOps adds another layer to troubleshoot.

When something fails, I need to understand both:

```text
Git / Helm
```

and:

```text
ArgoCD / Kubernetes
```

This was visible during the PostgreSQL Secret drift issue.

---

# Part 5 — Stretch Goals

# 5.1 Horizontal Pod Autoscaler

I added an HPA for the Development environment.

Configuration:

```text
Minimum replicas: 1
Maximum replicas: 4
Target CPU utilization: 50%
```

The HPA is enabled through:

```yaml
autoscaling:
  enabled: true
  minReplicas: 1
  maxReplicas: 4
  targetCPUUtilizationPercentage: 50
```

---

# 5.2 HPA Testing

The HPA was tested under load.

The application scaled from the lower replica count toward the configured maximum when CPU utilization increased.

After the load stopped and CPU utilization dropped, Kubernetes reduced the replica count again.

This verified that the HPA was not just configured but actually responded to resource utilization.

---

# 5.3 HPA Evidence

![HPA](screenshots/part-5-stretch/05-01-hpa-current-state.png)

The screenshot shows the HPA state after testing.

---

# 5.4 Observability Hooks

The Deployment includes Prometheus-style annotations:

```yaml
prometheus.io/scrape: "true"
prometheus.io/port: "8000"
prometheus.io/path: "/metrics"
```

These provide a standard integration point for a future Prometheus setup.

However, the provided application does not expose a `/metrics` endpoint.

Therefore, I did not claim that a complete Prometheus/Grafana monitoring system was implemented.

The observability approach is documented in:

```text
docs/observability.md
```

---

# 5.5 Secrets Management Proposal

For a real production deployment, I would avoid keeping database credentials directly in the Git repository.

The proposed architecture is:

```text
AWS Secrets Manager
        |
        v
External Secrets Operator
        |
        v
Kubernetes Secret
        |
        v
Notes API
```

The application would continue to use:

```text
secretKeyRef
```

while the actual secret value would be stored in AWS Secrets Manager.

The detailed proposal is documented in:

```text
docs/secrets-management-proposal.md
```

---

# 5.6 Future Security Improvements

For a production supply-chain setup I would also consider:

- SBOM generation
- Cosign image signing
- Signature verification
- Dependency update automation
- Container image policy enforcement
- Network policies
- Centralized logging
- Runtime security monitoring

These are proposed improvements and are not claims about completed implementation.

---

# 6. Final Validation

The final local Kubernetes environment was checked for:

```text
✓ Notes API pods running
✓ PostgreSQL running
✓ API health checks
✓ API readiness checks
✓ API database read/write operation
✓ Kubernetes Service
✓ HPA
✓ Dev ArgoCD Application
✓ Prod ArgoCD Application
✓ GitOps synchronization
✓ Helm dependency
✓ Helm lint
✓ Helm rendering
✓ Kubernetes security configuration
✓ Docker non-root execution
✓ GitHub Actions workflow
✓ Trivy image scanning
✓ Trivy configuration scanning
```

The final ArgoCD state was:

```text
notes-api-dev   Synced   Healthy
notes-api-prod  Synced   Healthy
```

Production had:

```text
2 API replicas
1 PostgreSQL pod
```

Development had HPA configured for:

```text
1–4 replicas
```

---

# 7. Final Validation Evidence

![Final cluster status](screenshots/final-validation/06-01-final-cluster-status%20%282%29.png)

This screenshot provides final cluster-level evidence.

---

# 8. Evidence Directory

The repository contains screenshots for the major implementation stages.

```text
screenshots/
│
├── part-1-docker/
│   └── 01-01-docker-desktop-image.png
│
├── part-2-kubernetes/
│   ├── 02-01-kubernetes-dev-deployment (2).png
│   └── 02-02-api-postgres-evidence.png
│
├── part-3-ci/
│   └── 03-01-github-actions-run.png
│
├── part-4-argocd/
│   ├── 04-01-argocd-applications.png
│   ├── 04-02-argocd-dev-resource-tree.png
│   └── 04-03-argocd-prod-resource-tree.png
│
├── part-5-stretch/
│   └── 05-01-hpa-current-state.png
│
└── final-validation/
    └── 06-01-final-cluster-status (2).png
```

The screenshots are supporting evidence and do not replace the implementation itself.

---

# 9. Main Troubleshooting Lessons

## 9.1 Docker

The Docker build was tested and the final runtime was verified as a non-root user.

This helped confirm that the Dockerfile was not only syntactically valid but also followed the intended runtime security model.

---

## 9.2 PostgreSQL Credentials

The most important Kubernetes issue was the PostgreSQL authentication mismatch.

The lesson was:

> A Kubernetes Secret existing in the cluster does not automatically mean that its value matches the password already stored inside an initialized PostgreSQL database.

The issue was diagnosed using password hashes without exposing the actual password.

---

## 9.3 ArgoCD OutOfSync

I learned that:

```text
Healthy
```

and:

```text
Synced
```

represent different things.

A Kubernetes workload can be healthy while ArgoCD still considers the live state different from the desired Git state.

---

## 9.4 HPA

The HPA showed that Kubernetes scaling depends on configured resource metrics and thresholds.

The number of API requests alone is not the HPA metric used in this configuration.

---

# 10. What I Would Improve for a Real Production Environment

The assignment was completed locally.

If I moved the architecture to AWS, I would consider:

```text
                       GitHub
                          |
                   GitHub Actions
                          |
              +-----------+-----------+
              |                       |
          Security                 Build
           Scans                  Image
              |                       |
              +-----------+-----------+
                          |
                     ECR Registry
                          |
                        ArgoCD
                          |
                       AWS EKS
                          |
              +-----------+-----------+
              |                       |
          Notes API              PostgreSQL
              |                   Amazon RDS
              |
             HPA
              |
       Load Balancer
```

Additional production improvements would include:

- AWS EKS
- Amazon ECR
- Amazon RDS PostgreSQL
- AWS Secrets Manager
- External Secrets Operator
- IAM Roles for Service Accounts
- Prometheus
- Grafana
- Centralized logging
- Network policies
- Pod disruption budgets
- SBOM
- Cosign
- Image signature verification

These are proposed future improvements and are not claimed as part of the current local implementation.

---

# 11. Trade-offs Summary

## Local kind instead of EKS

### Why

The assignment did not require a real AWS deployment.

### Trade-off

The environment does not represent all production AWS infrastructure.

### Future improvement

Move the same Helm/GitOps model to EKS.

---

## Bitnami PostgreSQL instead of managed database

### Why

The assignment specifically required PostgreSQL as a Helm dependency.

### Trade-off

A database running inside the local Kubernetes cluster does not provide the operational advantages of a managed database.

### Future improvement

Use Amazon RDS PostgreSQL for production.

---

## Manual production synchronization

### Why

It provides an intentional deployment point.

### Trade-off

A production change requires manual action.

### Future improvement

Keep manual approval for production but integrate it with a formal deployment approval workflow.

---

## Secrets outside Git

### Why

Database credentials should not be committed to the repository.

### Trade-off

The local environment required manual Secret handling.

### Future improvement

Use AWS Secrets Manager + External Secrets Operator.

---

## No full Prometheus/Grafana stack

### Why

The assignment did not require a complete monitoring platform and the provided application does not expose `/metrics`.

### Trade-off

The project does not demonstrate a complete monitoring dashboard.

### Future improvement

Add application metrics and deploy Prometheus/Grafana.

---

# 12. What I Learned

This assignment gave me hands-on experience with the complete DevOps workflow around a containerized application.

The main areas I practiced were:

- Writing a multi-stage Dockerfile
- Running containers as non-root
- Docker healthchecks
- Helm chart development
- Helm dependencies
- PostgreSQL deployment
- Kubernetes Secrets
- ConfigMaps
- Liveness and readiness probes
- Kubernetes security contexts
- Resource requests and limits
- Horizontal Pod Autoscaling
- GitHub Actions
- Ruff
- Trivy image scanning
- Trivy Kubernetes configuration scanning
- ArgoCD
- GitOps
- Kubernetes troubleshooting
- PostgreSQL authentication troubleshooting
- Understanding desired state vs live state
- Production-oriented secrets management

The troubleshooting work was especially useful because it required understanding how multiple components interact instead of only following installation commands.

---

# 13. Conclusion

This assignment gave me practical experience with the complete DevOps flow:

```text
Application
    |
    v
Docker
    |
    v
Helm
    |
    v
Kubernetes
    |
    v
GitHub Actions
    |
    v
Trivy
    |
    v
ArgoCD
    |
    v
GitOps
    |
    v
HPA / Production Improvements
```

The project was implemented locally using kind rather than AWS EKS because the assignment did not require a real cloud deployment.

The main focus was understanding the complete workflow, implementing the required components, validating them, and troubleshooting real issues encountered during deployment.

The most important practical lessons were around:

- Kubernetes Secret handling
- PostgreSQL credential consistency
- Kubernetes security configuration
- CI security gates
- ArgoCD desired-state reconciliation
- Production vs Development deployment policies
- HPA behavior

---

**Author:** Devansh Goswami

**MCA Student | Aspiring Cloud / DevOps Engineer**