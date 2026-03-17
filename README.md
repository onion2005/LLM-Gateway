# LLM Gateway

An OpenAI-compatible LLM gateway deployed on Kubernetes (EKS), proxying requests to AWS Bedrock.
Built to test and compare gateway solutions — LiteLLM today, Bifrost later.

## Architecture

```
                        ┌─────────────────────────────────────────────────────┐
                        │                  EKS Cluster (llmgw ns)             │
                        │                                                     │
  Client               │  ┌──────────────────────────────────────────────┐   │
  (curl / OpenAI SDK)  │  │              LiteLLM Proxy                   │   │
        │              │  │                                              │   │
        │  Bearer key  │  │  ┌────────────┐    ┌──────────────────────┐ │   │
        └─────────────►│  │  │  Auth &    │    │   Model Router       │ │   │
                        │  │  │  Budget    │───►│   claude-sonnet      │ │   │
                        │  │  │  (Postgres)│    │   claude-haiku       │ │   │
                        │  │  └────────────┘    │   claude-auto        │ │   │
                        │  │                    │   (cost-based)       │ │   │
                        │  │  ┌─────────────────┴──────────────────┐   │ │   │
                        │  │  │           Guardrail Pipeline        │   │ │   │
                        │  │  │                                     │   │ │   │
                        │  │  │  pre_call:                          │   │ │   │
                        │  │  │   1. Presidio  ── PII masking       │   │ │   │
                        │  │  │   2. Bedrock   ── content mod       │   │ │   │
                        │  │  │                   prompt injection  │   │ │   │
                        │  │  │  post_call:                         │   │ │   │
                        │  │  │   3. Presidio  ── PII masking       │   │ │   │
                        │  │  │   4. Bedrock   ── content mod       │   │ │   │
                        │  │  └──────────────────┬─────────────────┘   │ │   │
                        │  └─────────────────────┼────────────────────-┘ │   │
                        │                        │                        │   │
                        └────────────────────────┼────────────────────────┘
                                                 │ IRSA (pod IAM role)
                                                 ▼
                                    ┌────────────────────────┐
                                    │      AWS Bedrock        │
                                    │  Claude Sonnet 4.6      │
                                    │  Claude Haiku 4.5       │
                                    │  (cross-region profiles)│
                                    └────────────────────────┘
```

## Request Flow

```
Client request
  → Auth check (virtual key → team → budget check via Postgres)
  → pre_call guardrails:
      Presidio: mask PII in prompt
      Bedrock:  block hate / violence / prompt injection
  → Model router (cost-based: haiku default, sonnet fallback for claude-auto)
  → AWS Bedrock (via IRSA, no static credentials)
  → post_call guardrails:
      Presidio: mask PII in response
      Bedrock:  block harmful content in response
  → Response returned to client
```

## Team Access Control

| Team           | claude-haiku | claude-sonnet | claude-auto | Budget  |
|----------------|:---:|:---:|:---:|---------|
| feature-team1  | ✅  | ❌  | ❌  | $50/mo  |
| feature-team2  | ✅  | ❌  | ❌  | $50/mo  |
| feature-team3  | ✅  | ✅  | ✅  | $200/mo |
| feature-team4  | ✅  | ✅  | ✅  | $200/mo |
| **Global cap** |     |     |     | **$600/mo** |

## Stack

| Layer | Technology |
|---|---|
| Gateway | LiteLLM (`ghcr.io/berriai/litellm:main-latest`) |
| Compute | EKS — cluster `charming-electro-pumpkin`, namespace `llmgw` |
| Models | AWS Bedrock — Claude Sonnet 4.6, Claude Haiku 4.5 |
| Auth / Spend | PostgreSQL (team keys, budgets, spend logs) |
| PII redaction | Presidio (analyzer + anonymizer sidecars) |
| Content moderation | Bedrock Guardrails (`id`) |
| Credentials | IRSA (no static AWS keys) |
| IaC | Terraform |
| Alerts | Slack webhook at 80% budget threshold |

## Quick Start

```bash
# Port-forward the gateway
kubectl -n llmgw port-forward svc/litellm 4000:4000

# Issue a team key (requires master key)
curl -X POST http://localhost:4000/key/generate \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"team_id": "feature-team1", "duration": "24h"}'

# Call the gateway
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer <team-key>" \
  -H "Content-Type: application/json" \
  -d '{"model": "claude-haiku", "messages": [{"role": "user", "content": "Hello"}]}'

# Run validation tests
python3 tests/validate_gateway.py
```

## Production Considerations

Items intentionally out of scope for this repo, with notes on how they'd be handled in a full org setup:

| Concern | Status | Production approach |
|---|---|---|
| SSO / IdP integration | Out of scope | LiteLLM supports OIDC/SAML; team keys would be issued via an internal developer portal backed by the org's IdP (Okta, Azure AD) |
| Secret rotation | Manual | AWS Secrets Manager + External Secrets Operator; rotate master key and Postgres password on a schedule via Lambda or a CronJob |
| Audit logging | Not configured | CloudTrail for AWS API calls; LiteLLM request logs shipped to CloudWatch Logs or an ELK stack for per-request audit trail (who called what model, when, with what key) |
| AlertManager rules | Not configured | Prometheus AlertManager with rules for: error rate > 5%, p99 latency > 10s, team budget burn rate on track to exceed cap before month end, guardrail block spike |
| Network observability | Not configured | VPC Flow Logs + CloudTrail; in-cluster: Cilium Hubble or similar for east-west traffic visibility |
| Multi-region / DR | Not configured | Bedrock cross-region inference profiles are already in use; active-passive failover would add a second EKS cluster in us-west-2 with Route53 health checks |
| Image scanning | Not configured | ECR image scanning (or Trivy in CI) on every build; policy to block deployment of images with critical CVEs |
| Resource quotas | Not configured | `ResourceQuota` per namespace to prevent a runaway deployment from exhausting cluster capacity |

## Project Structure

```
terraform/                — VPC, EKS, IAM, Bedrock guardrail, remote state backend
k8s/                      — Secrets, ConfigMap, Deployments, Services, HPA, PDB
.github/workflows/        — CI (validate + test on PR), Deploy (manual approval)
tests/                    — End-to-end validation (20 tests)
```
