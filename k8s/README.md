# Summariser — Kubernetes Manifests

Deploys the LiteLLM gateway and FastAPI backend onto the `charming-electro-pumpkin` EKS cluster.

---

## Namespace Layout

| Namespace | Workload | Purpose |
|---|---|---|
| `llmgw` | LiteLLM | OpenAI-compatible proxy to AWS Bedrock |
| `summariser` | FastAPI app | Business logic: presigned URLs, DynamoDB polling, transcript fetching |

---

## Files

| File | Contents |
|---|---|
| `00-namespaces.yaml` | `llmgw` and `summariser` namespaces |
| `01-secrets.yaml` | LiteLLM master key Secret (template — fill in before applying) |
| `02-configmap-litellm.yaml` | LiteLLM `config.yaml`: model list, timeouts |
| `03-serviceaccounts.yaml` | IRSA-annotated ServiceAccounts for both workloads |
| `04-litellm.yaml` | LiteLLM Deployment (2 replicas) + ClusterIP Service |
| `05-app.yaml` | FastAPI Deployment (2 replicas) + ClusterIP Service |
| `06-networkpolicy.yaml` | Default-deny ingress + scoped allow rules |

---

## Deployment Order

```bash
# 1. Prerequisites — ensure kubeconfig is pointing at the right cluster
aws eks update-kubeconfig --name charming-electro-pumpkin --region us-east-1

# 2. Namespaces first
kubectl apply -f 00-namespaces.yaml

# 3. Fill in the master key, then apply secrets (do NOT commit with real values)
#    Generate: openssl rand -hex 32
vi 01-secrets.yaml
kubectl apply -f 01-secrets.yaml

# 4. ConfigMap and ServiceAccounts
kubectl apply -f 02-configmap-litellm.yaml
kubectl apply -f 03-serviceaccounts.yaml

# 5. Workloads
kubectl apply -f 04-litellm.yaml
kubectl apply -f 05-app.yaml

# 6. Network policies
kubectl apply -f 06-networkpolicy.yaml
```

Or apply all at once (after filling in secrets):
```bash
kubectl apply -f .
```

---

## Security Design

### IRSA — No Static Credentials
Both pods authenticate to AWS using IAM Roles for Service Accounts. No access keys, no secrets mounted with AWS credentials.

| ServiceAccount | Namespace | IAM Role | Permissions |
|---|---|---|---|
| `litellm-app` | `llmgw` | `litellm-irsa` | `bedrock:InvokeModel`, `bedrock:InvokeModelWithResponseStream` |
| `summariser-app` | `summariser` | `summariser-app-irsa` | S3 read (transcripts/), S3 put (videos/), DynamoDB read, Bedrock invoke, KMS decrypt |

### Network Policies — Default Deny
Both namespaces have a **default-deny-all-ingress** policy. Traffic is only permitted via explicit allow rules:
- `summariser-app` → `litellm` on port 4000 (cross-namespace, pod-level selector)
- Inbound to `summariser-app` on port 8000 (for CLI port-forward / future ingress)

### Pod Security
All containers are configured with:
- `runAsNonRoot: true` — no root processes
- `allowPrivilegeEscalation: false`
- `capabilities: drop: ["ALL"]` — no Linux capabilities
- `readOnlyRootFilesystem: true` on the FastAPI app (`/tmp` mounted as emptyDir for scratch space)

### Secrets Management
The LiteLLM master key is stored as a Kubernetes Secret (base64, etcd-encrypted at rest on EKS by default). For stricter compliance, replace with [AWS Secrets Manager + External Secrets Operator](https://external-secrets.io/).

---

## Useful Commands

```bash
# Check pod status
kubectl -n llmgw get pods
kubectl -n summariser get pods

# LiteLLM logs
kubectl -n llmgw logs deploy/litellm

# FastAPI app logs
kubectl -n summariser logs deploy/summariser-app

# Port-forward LiteLLM for local testing
kubectl -n llmgw port-forward svc/litellm 4000:4000

# Port-forward FastAPI app for local testing
kubectl -n summariser port-forward svc/summariser-app 8000:8000

# Verify IRSA is working (should show assumed role, not node role)
kubectl -n llmgw exec deploy/litellm -- aws sts get-caller-identity
kubectl -n summariser exec deploy/summariser-app -- aws sts get-caller-identity
```

---

## Prerequisites

- EKS cluster `charming-electro-pumpkin` running
- OIDC provider associated (`eksctl utils associate-iam-oidc-provider`)
- Terraform applied (IRSA roles, S3, DynamoDB, KMS provisioned)
- FastAPI Docker image built and pushed to ECR (update image in `05-app.yaml`)

