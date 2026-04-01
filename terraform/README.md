# LLM Gateway — Terraform Infrastructure

Terraform configuration for the LLM Gateway. Manages the Bedrock Guardrail and the LiteLLM IRSA role, scoped to an existing VPC/EKS environment.

---

## Resources Created

### IAM
| Resource | Name | Purpose |
|---|---|---|
| `aws_iam_role` | `litellm-irsa` | IRSA role for the LiteLLM pod: Bedrock invoke + ApplyGuardrail |

### Bedrock
| Resource | Name | Purpose |
|---|---|---|
| `aws_bedrock_guardrail` | `llmgw-content-guardrail` | Content moderation (hate, violence, sexual, insults, misconduct) + prompt injection blocking |
| `aws_bedrock_guardrail_version` | `v1` | Published version — LiteLLM requires a specific version, not DRAFT |

---

## Security Design

### IRSA — No Static Credentials
LiteLLM authenticates to AWS via IRSA (IAM Roles for Service Accounts). The role is scoped to `system:serviceaccount:llmgw:litellm-app` and permits only `bedrock:InvokeModel`, `bedrock:InvokeModelWithResponseStream`, and `bedrock:ApplyGuardrail`.

### Bedrock Guardrail
Applied on both input (`pre_call`) and output (`post_call`) for all teams. Blocks hate speech, violence, sexual content, insults, misconduct, and prompt injection attempts at HIGH sensitivity.

---

## Prerequisites

- Existing EKS cluster with OIDC provider associated
- AWS credentials with sufficient IAM + Bedrock permissions
- Terraform >= 1.5

## Variables

| Variable | Description |
|---|---|
| `aws_region` | AWS region (e.g. `us-east-1`) |
| `eks_oidc_provider_url` | OIDC URL without `https://` prefix |
| `eks_oidc_provider_arn` | OIDC provider ARN |

Copy `variables.tf.example` to `terraform.tfvars` and fill in the values before running.

## Usage

```bash
terraform init
terraform plan
terraform apply
```

## Outputs

| Output | Description |
|---|---|
| `litellm_irsa_role_arn` | Annotate the `litellm-app` Kubernetes service account with this ARN |
| `bedrock_guardrail_id` | Copy into `k8s/01-secrets.yaml` → `bedrock-guardrail-secret` |
| `bedrock_guardrail_version` | Copy into `k8s/01-secrets.yaml` → `bedrock-guardrail-secret` |

## Remote State

State lives in S3 (`llmgw-tfstate-409633134924`) with DynamoDB locking (`llmgw-tfstate-lock`). See `backend.tf` for bootstrap commands.
