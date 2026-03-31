# LLM Gateway — Kubernetes Manifests

Deploys the LiteLLM gateway onto the `charming-electro-pumpkin` EKS cluster.

---

## Namespace Layout

| Namespace | Workload | Purpose |
|---|---|---|
| `llmgw` | LiteLLM | OpenAI-compatible proxy to AWS Bedrock |

---

## Files

| File | Contents |
|---|---|
| `00-namespaces.yaml` | `llmgw` namespace |
| `01-secrets.yaml` | LiteLLM master key, Bedrock guardrail IDs, Grafana password (template — fill in before applying) |
| `02-configmap-litellm.yaml` | LiteLLM `config.yaml`: model list, timeouts |
| `03-serviceaccounts.yaml` | IRSA-annotated ServiceAccount for LiteLLM |
| `04-litellm.yaml` | LiteLLM Deployment + HPA + PDB + ClusterIP Service |
| `06-networkpolicy.yaml` | Default-deny ingress + scoped allow rules for `llmgw` |
| `07-monitoring.yaml` | Prometheus + Grafana (persistent gp3 PVCs) |
| `08-ingress.yaml` | ingress-nginx rules |
| `09-postgres.yaml` | PostgreSQL Deployment + persistent gp3 PVC + Service |
| `10-presidio.yaml` | Presidio Analyzer + Anonymizer for PII redaction |

---

## Deployment Order

```bash
# 1. Prerequisites — ensure kubeconfig is pointing at the right cluster
aws eks update-kubeconfig --name charming-electro-pumpkin --region us-east-1

# 2. Namespaces first
kubectl apply -f 00-namespaces.yaml

# 3. Fill in the master key and guardrail IDs, then apply secrets (do NOT commit with real values)
#    Generate: openssl rand -hex 32
vi 01-secrets.yaml
kubectl apply -f 01-secrets.yaml

# 4. ConfigMap and ServiceAccount
kubectl apply -f 02-configmap-litellm.yaml
kubectl apply -f 03-serviceaccounts.yaml

# 5. Workload
kubectl apply -f 04-litellm.yaml

# 6. Network policies, monitoring, ingress, postgres, presidio
kubectl apply -f 06-networkpolicy.yaml
kubectl apply -f 07-monitoring.yaml
kubectl apply -f 08-ingress.yaml
kubectl apply -f 09-postgres.yaml
kubectl apply -f 10-presidio.yaml
```

Or apply all at once (after filling in secrets):
```bash
kubectl apply -f .
```

---

## Security Design

### IRSA — No Static Credentials
LiteLLM authenticates to AWS using IAM Roles for Service Accounts. No access keys, no secrets mounted with AWS credentials.

| ServiceAccount | Namespace | IAM Role | Permissions |
|---|---|---|---|
| `litellm-app` | `llmgw` | `litellm-irsa` | `bedrock:InvokeModel`, `bedrock:InvokeModelWithResponseStream`, `bedrock:ApplyGuardrail` |

### Network Policies — Default Deny
The `llmgw` namespace has a **default-deny-all-ingress** policy. Traffic is only permitted via explicit allow rules:
- External clients → `litellm` on port 4000 (via ingress-nginx)
- `litellm` → `postgres` on port 5432 (same namespace)
- `litellm` → `presidio-analyzer` / `presidio-anonymizer` on port 3000 (same namespace)

### Pod Security
All containers are configured with:
- `runAsNonRoot: true` — no root processes
- `allowPrivilegeEscalation: false`
- `capabilities: drop: ["ALL"]` — no Linux capabilities

### Secrets Management
The LiteLLM master key is stored as a Kubernetes Secret (base64, etcd-encrypted at rest on EKS by default). For stricter compliance, replace with [AWS Secrets Manager + External Secrets Operator](https://external-secrets.io/).

---

## Useful Commands

```bash
# Check pod status
kubectl -n llmgw get pods

# LiteLLM logs
kubectl -n llmgw logs deploy/litellm

# Port-forward LiteLLM for local testing
kubectl -n llmgw port-forward svc/litellm 4000:4000

# Verify IRSA is working (should show assumed role, not node role)
kubectl -n llmgw exec deploy/litellm -- aws sts get-caller-identity

# Run validation tests (requires port-forward)
python3 ../tests/validate_gateway.py
```

---

## Prerequisites

- EKS cluster `charming-electro-pumpkin` running
- OIDC provider associated (`eksctl utils associate-iam-oidc-provider`)
- Terraform applied (litellm-irsa role, Bedrock guardrail provisioned)
