# Summariser — Terraform Infrastructure

Production infrastructure for the Video Summariser pipeline. Deploys S3, Lambda, DynamoDB, EventBridge, KMS, IAM, and VPC endpoints into an existing VPC/EKS environment.

---

## Architecture

```
S3 upload (videos/)
  └─ S3 Event ──► Lambda: start-transcribe
                    └─ Amazon Transcribe (zh-CN) ──► S3 (transcripts/)
                                                       └─ EventBridge (job complete)
                                                            └─ Lambda: notify
                                                                 └─ DynamoDB (status update)

CLI ──► FastAPI (EKS) ──► polls DynamoDB ──► fetches transcript ──► LiteLLM (EKS) ──► Bedrock
```

All AWS API calls from Lambda travel over **private VPC endpoints** — no traffic exits to the public internet.

---

## Resources Created

### Storage
| Resource | Name | Purpose |
|---|---|---|
| `aws_s3_bucket` | `summariser-bucket-<account-id>` | Stores videos/, audio/, transcripts/ |
| `aws_s3_bucket_lifecycle_configuration` | — | Auto-deletes videos after 7d, audio after 3d |
| `aws_s3_bucket_public_access_block` | — | All public access blocked |
| `aws_s3_bucket_server_side_encryption_configuration` | — | SSE-KMS with bucket key |
| `aws_dynamodb_table` | `transcribe-jobs` | Job status tracking: job_id, status, s3 keys, timestamps |

### Compute
| Resource | Name | Purpose |
|---|---|---|
| `aws_lambda_function` | `start-transcribe` | Triggered by S3 upload; starts Transcribe job, writes initial DynamoDB record |
| `aws_lambda_function` | `transcribe-notify` | Triggered by EventBridge; updates DynamoDB on job completion/failure |

### Eventing
| Resource | Name | Purpose |
|---|---|---|
| `aws_s3_bucket_notification` | — | Routes `s3:ObjectCreated:*` under `videos/` to `start-transcribe` Lambda |
| `aws_cloudwatch_event_rule` | `transcribe-job-complete` | Matches Transcribe `COMPLETED` / `FAILED` state changes |
| `aws_cloudwatch_event_target` | — | Routes rule to `transcribe-notify` Lambda |

### IAM
| Resource | Name | Purpose |
|---|---|---|
| `aws_iam_role` | `lambda-start-transcribe` | Execution role: S3 read, Transcribe start, DynamoDB write, KMS, VPC ENI |
| `aws_iam_role` | `lambda-notify` | Execution role: DynamoDB update, KMS, VPC ENI |
| `aws_iam_role` | `summariser-app-irsa` | IRSA role for FastAPI pod: S3 read, DynamoDB read, Bedrock invoke, KMS |

### Encryption
| Resource | Name | Purpose |
|---|---|---|
| `aws_kms_key` | — | Symmetric CMK, auto-rotation enabled, 7-day deletion window |
| `aws_kms_alias` | `alias/summariser` | Human-readable alias for the key |

### Networking
| Resource | Name | Purpose |
|---|---|---|
| `aws_security_group` | `summariser-lambda` | Lambda SG: egress restricted to HTTPS within VPC CIDR only |
| `aws_security_group` | `summariser-vpc-endpoints` | Endpoint SG: ingress HTTPS from Lambda SG only |
| `aws_vpc_endpoint` | S3 (Gateway) | Free gateway; S3 traffic stays on AWS backbone |
| `aws_vpc_endpoint` | DynamoDB (Gateway) | Free gateway; DynamoDB traffic stays on AWS backbone |
| `aws_vpc_endpoint` | Transcribe (Interface) | Private DNS; Lambda calls Transcribe without internet |
| `aws_vpc_endpoint` | Lambda (Interface) | Private DNS; EKS pods invoke Lambda without internet |

---

## Security Design

### Network Isolation
Lambda functions run inside the VPC (`us-east-1a`, `us-east-1b`) with **no internet egress**. All outbound traffic is confined to HTTPS within the VPC CIDR (`172.31.0.0/16`) and routed exclusively through VPC endpoints.

> **Note on subnet design:** The existing VPC uses public subnets only (no VPN/NAT Gateway). Lambda does not receive a public IP when placed inside a VPC regardless of subnet type — the public subnet designation has no effect on Lambda. Traffic isolation is enforced entirely through security groups and VPC endpoint routing. If private subnets are added in future, the `lambda_subnet_ids` variable can be updated with no other changes required.

### Encryption at Rest
- **S3**: SSE-KMS with `bucket_key_enabled = true` (reduces KMS API calls ~99% via per-bucket data key caching)
- **DynamoDB**: KMS-managed server-side encryption
- **Lambda environment variables**: encrypted with the same CMK
- **Single CMK** (`alias/summariser`) covers all three services; key rotation is automatic (annual)

### Encryption in Transit
All service calls use HTTPS/TLS. Interface VPC endpoints enforce TLS termination within the AWS network — traffic never traverses the public internet.

### Least-Privilege IAM
Each Lambda has a **dedicated execution role** scoped to exactly the actions it needs:

| Role | Allowed actions |
|---|---|
| `lambda-start-transcribe` | `s3:GetObject` (videos/), `transcribe:StartTranscriptionJob`, `s3:PutObject` (transcripts/), `dynamodb:PutItem`, KMS decrypt, VPC ENI management |
| `lambda-notify` | `dynamodb:UpdateItem`, KMS decrypt, VPC ENI management |
| `summariser-app-irsa` | `s3:GetObject` + `s3:ListBucket` (transcripts/), `s3:PutObject` (videos/ for presigned URLs), `dynamodb:GetItem` + `dynamodb:Query`, `bedrock:InvokeModel` + `bedrock:InvokeModelWithResponseStream`, KMS decrypt |

The FastAPI app authenticates to AWS via **IRSA** (IAM Roles for Service Accounts) — no static credentials, no long-lived access keys.

### S3 Hardening
- All public access blocked at bucket level
- No bucket policy granting cross-account or public access
- KMS encryption required on all objects (enforced by default encryption config)
- Short lifecycle rules reduce attack surface: videos auto-deleted after 7 days, audio after 3 days

---

## Cost Estimate (~10 videos/month, 1hr average)

| Component | Monthly |
|---|---|
| S3 (storage + requests) | ~$0.50 |
| Amazon Transcribe ($0.024/min) | ~$14.40 |
| Bedrock Claude Sonnet 4.5 | ~$5.30 |
| Lambda (free tier) | ~$0 |
| DynamoDB (on-demand, free tier) | ~$0 |
| EventBridge | ~$0 |
| KMS (1 key + API calls) | ~$1 |
| VPC Gateway endpoints (S3, DynamoDB) | **Free** |
| VPC Interface endpoints (Transcribe, Lambda) — 2 AZ | ~$28 |
| **Pipeline total** | **~$49/month** |
| EKS cluster + nodes (pre-existing) | ~$140/month |
| **Grand total** | **~$189/month** |

---

## Prerequisites

- Existing EKS cluster with OIDC provider associated
- AWS credentials with sufficient IAM permissions
- Terraform >= 1.5

## Usage

```bash
terraform init
terraform plan
terraform apply
```

After apply, annotate the Kubernetes service account to activate IRSA:

```bash
kubectl -n summariser create serviceaccount summariser-app
kubectl -n summariser annotate serviceaccount summariser-app \
  eks.amazonaws.com/role-arn=$(terraform output -raw app_irsa_role_arn)
```

## Outputs

| Output | Description |
|---|---|
| `bucket_name` | S3 bucket name |
| `dynamodb_table_name` | DynamoDB table name |
| `app_irsa_role_arn` | IAM role ARN to annotate the K8s service account |
