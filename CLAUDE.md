# LLM Gateway

## What This Is
An OpenAI-compatible LLM gateway deployed on EKS, proxying requests to AWS Bedrock.
Built to test and compare different gateway solutions (LiteLLM now, Bifrost later) on Kubernetes.

## Key Decisions
- **LiteLLM** — fast setup, OpenAI-compatible, native Bedrock support. May swap to Bifrost later for performance comparison
- **EKS** — justified because we want to test different gateways on K8s
- **IRSA** — pod-level IAM credentials for Bedrock and S3 access, no static keys

## Infrastructure
- **AWS Region**: us-east-1
- **EKS Cluster**: `charming-electro-pumpkin` (public API endpoint with IP allowlist, private worker nodes)
- **EKS Access**: API mode, access entry for `ml-learning-user` with cluster admin policy
- **Namespace**: `llmgw`
- **Bedrock models**: Claude Sonnet 4.6, Claude Haiku 4.5 (via cross-region inference profiles)

## Tech Stack
- **LLM Gateway**: LiteLLM (ghcr.io/berriai/litellm:main-latest)
- **Database**: PostgreSQL (for key/team/spend tracking)
- **IaC**: Terraform (VPC, EKS, IAM, Bedrock guardrail)
- **K8s manifests**: k8s/

## Project Structure
```
terraform/    — VPC, EKS, IAM, Bedrock guardrail (terraform-aws-modules)
k8s/          — Namespace, Secrets, ConfigMap, Deployments, Services
tests/        — validate_gateway.py — end-to-end validation script
```

## Commands
```bash
# Check pods
kubectl -n llmgw get pods

# Port-forward gateway locally
kubectl -n llmgw port-forward svc/litellm 4000:4000

# Logs
kubectl -n llmgw logs deploy/litellm

# Run validation tests (requires port-forward)
python3 tests/validate_gateway.py
```

## Master Key
Stored in `.envrc` as `MASTER_KEY`. Must include `sk-` prefix (LiteLLM requirement).

## CI/CD
- **CI** (`.github/workflows/ci.yml`): runs on every PR — terraform fmt/validate, yamllint, kubectl dry-run, integration tests against live cluster (main only, via OIDC)
- **Deploy** (`.github/workflows/deploy.yml`): manual `workflow_dispatch` — choose `k8s`, `terraform`, or `all`. Requires `production` environment approval in GitHub.
- **Secrets needed in GitHub**: `AWS_CI_ROLE_ARN`, `LITELLM_MASTER_KEY`
- **OIDC**: no static AWS credentials in CI — IAM role federates via GitHub Actions OIDC provider

## Terraform Remote State
State lives in S3 (`llmgw-tfstate-409633134924`) with DynamoDB locking (`llmgw-tfstate-lock`).
Bootstrap the bucket once with the commands in `terraform/backend.tf`, then `terraform init -migrate-state`.

## What's Done
- [x] EKS cluster + VPC (Terraform)
- [x] LiteLLM deployed on EKS with IRSA
- [x] PostgreSQL for key/team/spend tracking (persistent gp3 PVC)
- [x] Multi-team access control (4 teams, model restrictions)
- [x] Per-team and global budget limits + Slack alerts
- [x] PII redaction via Presidio (input + output)
- [x] Content moderation + prompt injection blocking via Bedrock Guardrails
- [x] HPA (2–5 replicas, CPU 70%) + PDB (minAvailable: 1)
- [x] Persistent Prometheus + Grafana storage (gp3 PVCs)
- [x] Grafana password from Secret (not hardcoded)
- [x] Terraform remote state (S3 + DynamoDB lock)
- [x] CI/CD via GitHub Actions (OIDC, no static credentials)
- [x] Validation tests (20/20 passing)

## What's Next
- [ ] AlertManager rules (high error rate, budget burn, latency)
- [ ] Centralized logging (CloudWatch or ELK)
- [ ] Compare LiteLLM vs Bifrost gateway performance
- [ ] IAM role + OIDC provider for GitHub Actions CI (bootstrap once)
- [ ] Production hardening (secret rotation, CloudTrail, VPC Flow Logs)
