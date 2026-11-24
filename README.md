# DevOps Engineer Assessment — Full Solution

> **Final image size:** ~45 MB (Python 3.12-Alpine multi-stage build)

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start — Local App](#quick-start--local-app)
3. [Observability Stack](#observability-stack)
4. [Running Tests](#running-tests)
5. [System Health Script](#system-health-script)
6. [Terraform (AWS)](#terraform-aws)
7. [Kubernetes Deployment](#kubernetes-deployment)
8. [Architecture Diagram](#architecture-diagram)
9. [CI/CD Secrets & Variables](#cicd-secrets--variables)
10. [Design Decisions](#design-decisions)
11. [Deployment & Rollback Strategy](#deployment--rollback-strategy)
12. [Security Considerations](#security-considerations)
13. [AWS Cost Estimate](#aws-cost-estimate)
14. [What I Would Improve](#what-i-would-improve)
15. [AI Tool Usage](#ai-tool-usage)

---

## Prerequisites

| Tool | Version |
|---|---|
| Docker & Docker Compose v2 | ≥ 24 |
| Python | ≥ 3.12 |
| Terraform | ≥ 1.9 |
| kubectl | ≥ 1.30 |
| kind / minikube / k3d | any recent |
| AWS CLI | ≥ 2 |
| bash | ≥ 5 (for scripts) |

---

## Quick Start — Local App

```bash
# 1. Clone
git clone https://github.com/YOUR_ORG/devops-task.git
cd devops-task

# 2. Build & run
docker compose up --build -d

# 3. Test endpoints
curl http://localhost:8080/
# {"message":"Hello from DevOps Task!","status":"running","version":"1.0.0"}

curl http://localhost:8080/health
# {"status":"healthy","version":"1.0.0","env":"local"}

curl http://localhost:8080/metrics
# # HELP http_requests_total ...
```

---

## Observability Stack

```bash
# Set Grafana admin password (required — not hardcoded)
export GRAFANA_ADMIN_PASSWORD=mysecretpassword

# Start the full monitoring stack
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d

# Access Grafana
open http://localhost:3000
# Login: admin / <your GRAFANA_ADMIN_PASSWORD>
```

### Available Dashboards

| Dashboard | URL path in Grafana |
|---|---|
| Application (request rate, error rate, latency p50/p95/p99) | Dashboards → Application |
| Host (CPU, memory, disk, network) | Dashboards → Host |
| Containers (per-container CPU & memory vs limit) | Dashboards → Containers |

> **Investigating an error spike:** When the Application dashboard shows an error spike,
> switch to the Logs panel on the same dashboard (linked to Loki), filter by `level=error`,
> and correlate timestamps. The structured JSON logs expose `path`, `method`, and `status_code`
> as Loki label filters, letting you narrow down the failing endpoint instantly.

### Ports exposed to host

| Service | Port |
|---|---|
| App | 8080 |
| Grafana | 3000 |

All other services (Prometheus, Loki, Alloy, Node Exporter, cAdvisor) are on the internal `monitoring` Docker network only.

### cAdvisor & Node Exporter mounts

| Container | Mount | Reason |
|---|---|---|
| node-exporter | `/:/host:ro` | Read host kernel/proc metrics |
| node-exporter | `pid: host` | Accurate process stats |
| cadvisor | `/:/rootfs:ro`, `/sys`, `/var/lib/docker` | Container resource tracking |
| cadvisor | `privileged: true` | Required for cgroup v2 access |

---

## Running Tests

```bash
cd app
pip install -r requirements-dev.txt

# Run with coverage
pytest test_main.py --cov=main --cov-report=term-missing -v

# Lint
ruff check .
```

---

## System Health Script

```bash
# Copy to server
sudo cp scripts/system_health.sh /opt/scripts/system_health.sh
sudo chmod +x /opt/scripts/system_health.sh

# Run with defaults
./scripts/system_health.sh

# Run with custom thresholds, JSON output
./scripts/system_health.sh --cpu 80 --mem 70 --disk 75 --json

# Install as systemd timer (every 5 minutes)
sudo cp scripts/system-health.service /etc/systemd/system/
sudo cp scripts/system-health.timer   /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now system-health.timer

# Or use cron
sudo cp scripts/system_health.cron /etc/cron.d/system-health
```

**Exit codes:** `0` = healthy, `1` = one or more thresholds exceeded (warning), `2` = critical (disk ≥ 95%)

---

## Terraform (AWS)

```bash
cd terraform

# Bootstrap remote state (one-time)
aws s3 mb s3://devops-task-tfstate
aws dynamodb create-table \
  --table-name devops-task-tflock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

# Staging
terraform init
terraform plan  -var-file=staging.tfvars
terraform apply -var-file=staging.tfvars

# Production
terraform plan  -var-file=production.tfvars
terraform apply -var-file=production.tfvars

# Teardown (always clean up)
terraform destroy -var-file=staging.tfvars
```

> **No static AWS keys are used.** GitHub Actions authenticates via OIDC (`role-to-assume`).
> The EC2 instance uses an IAM instance profile with least-privilege policies only.

---

## Kubernetes Deployment

```bash
# Start a local cluster
kind create cluster --name devops-task

# Apply all manifests
kubectl apply -f k8s/manifests.yaml
kubectl apply -f k8s/deployment.yaml

# Verify pods
kubectl -n devops-task get pods -w

# Access via port-forward (no ingress controller required locally)
kubectl -n devops-task port-forward svc/devops-task 8080:80 &
curl http://localhost:8080/health

# Zero-downtime rolling update
kubectl -n devops-task set image deployment/devops-task \
  app=YOUR_ECR_REPO/devops-task-service:sha-newsha

kubectl -n devops-task rollout status deployment/devops-task
# Waiting for deployment "devops-task" rollout to finish: 1 of 2 updated replicas...
# deployment "devops-task" successfully rolled out

# Rollback
kubectl -n devops-task rollout undo deployment/devops-task
# deployment.apps/devops-task rolled back
```

### Production on EKS differences

| Aspect | Local (kind) | EKS Production |
|---|---|---|
| Ingress | port-forward | AWS Load Balancer Controller + ACM cert |
| Secrets | plain K8s Secret | AWS Secrets Manager via External Secrets Operator |
| Autoscaling | HPA (CPU) | HPA + Karpenter for node autoscaling |
| IAM | n/a | IRSA (IAM Roles for Service Accounts) |
| Registry | ECR (public) | ECR (private, VPC endpoint) |

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                       GitHub Repository                          │
│                                                                   │
│  PR push → [pr-checks.yml]                                        │
│            ├── ruff lint + pytest + coverage                      │
│            ├── hadolint (Dockerfile) + shellcheck (scripts)       │
│            └── Trivy scan → FAIL on CRITICAL CVEs                │
│                                                                   │
│  main push → [deploy.yml]                                         │
│              ├── Multi-arch build (amd64 + arm64) with GHA cache │
│              ├── Tag: sha-<commit>, semver, NOT latest-only       │
│              ├── Push → Amazon ECR (via GitHub OIDC, no keys)    │
│              ├── SSM Run Command → EC2 docker pull + run          │
│              ├── Smoke test GET /health                           │
│              └── Auto-rollback if smoke test fails                │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                    ┌───────────▼───────────┐
                    │   Amazon ECR (images)  │
                    └───────────┬───────────┘
                                │
                    ┌───────────▼───────────┐
                    │   EC2 (Terraform)      │
                    │   - IAM instance profile│
                    │   - SG: port 8080 only │
                    │   - CW Logs retention  │
                    │   - IMDSv2 enforced    │
                    └───────────────────────┘

Kubernetes (local kind):
  Deployment (2 replicas, rolling update)
    ├── readiness + liveness → /health
    ├── securityContext: non-root, readOnlyRootFilesystem
    └── HPA (CPU 70%)

Observability (docker compose):
  App /metrics → Prometheus (15d retention)
  Node Exporter → Prometheus
  cAdvisor      → Prometheus
  All containers → Alloy → Loki (30d retention)
  Prometheus + Loki → Grafana (3 dashboards + 4 alerts)
```

---

## CI/CD Secrets & Variables

Configure these in **GitHub → Settings → Secrets and variables → Actions**:

| Name | Type | Description |
|---|---|---|
| `AWS_ACCOUNT_ID` | Secret | AWS account number |
| `AWS_REGION` | Secret | e.g. `us-east-1` |
| `AWS_ROLE_ARN` | Secret | OIDC role for GitHub Actions |
| `EC2_INSTANCE_ID` | Secret | Target EC2 instance ID |
| `EC2_PUBLIC_IP` | Secret | EC2 public IP for smoke test |
| `GRAFANA_ADMIN_PASSWORD` | Secret | Used locally via `.env` file |

---

## Design Decisions

| Decision | Choice | Reasoning |
|---|---|---|
| Language | Python FastAPI | Fastest to build, async, great Prometheus client support |
| Base image | Alpine 3.20 (multi-stage) | ~45 MB vs ~200 MB slim; distroless has no wget for HEALTHCHECK |
| Logs | structlog JSON → stdout | 12-factor; collected by Alloy without file mounts |
| Registry | ECR | Native AWS IAM integration, no extra credentials |
| Auth | GitHub OIDC | No long-lived access keys stored anywhere |
| Terraform state | S3 + DynamoDB | Standard, cheap, supports state locking |
| Loki labels | `level`, `service` only | Low cardinality; high-cardinality labels degrade Loki performance |
| EC2 vs ECS vs EKS | EC2 (task requirement) | Lower complexity for assessment; ECS Fargate preferred for real production |
| Image tagging | `sha-<commit>` + semver | Traceable and rollback-safe; `latest` alone is non-deterministic |

---

## Deployment & Rollback Strategy

1. **PR merged to main** → GitHub Actions builds, scans, and pushes the image tagged `sha-<commit>`.
2. **SSM Run Command** pulls the new image on EC2 and hot-swaps the container (`docker stop` → `docker run`).
3. **Smoke test** hits `GET /health` up to 5× (10 s apart). If all fail, the previous image tag (stored in SSM Parameter Store) is re-pulled and re-run automatically.
4. **Kubernetes** uses `kubectl rollout undo` to revert to the previous `ReplicaSet` instantly, with zero downtime because the rolling strategy keeps `maxUnavailable: 0`.

---

## Security Considerations

| Area | Measure |
|---|---|
| Secrets | Zero hardcoded secrets; env vars from GitHub Secrets / SSM |
| Image | Trivy scan on every PR, pipeline fails on CRITICAL CVEs |
| IAM | Least-privilege instance profile + OIDC role (no static keys) |
| Container | Non-root user, read-only root filesystem, all capabilities dropped |
| EC2 | Security group: port 8080 only; IMDSv2 enforced (no IMDSv1) |
| Grafana | Admin password from env var; only port 3000 exposed to host |
| Kubernetes | `securityContext` per pod + container; Secrets not committed in plaintext |
| Network | Monitoring stack on internal Docker network; only Grafana exposed |

---

## AWS Cost Estimate

| Resource | Monthly cost (us-east-1) |
|---|---|
| EC2 t3.micro (Free Tier 1st year) | \$0 / \$8.47 after |
| ECR storage (< 500 MB) | \$0.05 |
| CloudWatch Logs (1 GB / month) | \$0.50 |
| S3 state bucket | \$0.023/GB ≈ \$0.01 |
| DynamoDB (PAY_PER_REQUEST, low traffic) | < \$0.01 |
| **Total estimate** | **~\$9/month** |

---

## What I Would Improve

- **Helm chart** — package k8s manifests with separate `values-staging.yaml` / `values-prod.yaml`
- **External Secrets Operator** — replace plain K8s Secrets with AWS Secrets Manager integration
- **Alertmanager** — add Slack/Discord routing for Prometheus alerts
- **SBOM + Cosign** — sign images and generate a software bill of materials in the pipeline
- **OpenTelemetry** — add distributed tracing with Grafana Tempo for multi-service correlation
- **ECS Fargate** — replace EC2 for truly serverless container hosting without AMI management
- **Automated Terraform tests** — add `terratest` for infrastructure unit tests
- **Multi-environment Grafana** — use Terraform to provision Grafana Cloud per environment

---

## AI Tool Usage

This solution was built with the assistance of an AI coding assistant (Antigravity/Gemini) to:
- Scaffold boilerplate (FastAPI app structure, GitHub Actions YAML, Terraform HCL)
- Suggest Prometheus metric naming conventions
- Review security context settings for Kubernetes

Every file has been reviewed line-by-line and all configuration choices (image tags, threshold values, IAM policies, Loki label design) reflect deliberate engineering decisions I can explain and defend.
