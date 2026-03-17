variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "S3 bucket name for videos, audio, and transcripts"
  type        = string
  default     = "summariser-bucket-409633134924"
}

variable "eks_oidc_provider_url" {
  description = "EKS OIDC provider URL without https:// prefix (e.g. oidc.eks.us-east-1.amazonaws.com/id/XXXX)"
  type        = string
  default     = "oidc.eks.us-east-1.amazonaws.com/id/6E1D7B89FFB6D373BE71A25FF0F48E14"
}

variable "eks_oidc_provider_arn" {
  description = "EKS OIDC provider ARN"
  type        = string
  default     = "arn:aws:iam::409633134924:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/6E1D7B89FFB6D373BE71A25FF0F48E14"
}

variable "app_service_account_namespace" {
  description = "Kubernetes namespace of the app service account"
  type        = string
  default     = "summariser"
}

variable "app_service_account_name" {
  description = "Kubernetes service account name for the FastAPI app"
  type        = string
  default     = "summariser-app"
}

variable "vpc_id" {
  description = "VPC ID where Lambda functions and VPC endpoints will be deployed"
  type        = string
  default     = "vpc-0864483c93197733a"
}

variable "lambda_subnet_ids" {
  description = "Subnet IDs for Lambda VPC placement (2 AZs for HA)"
  type        = list(string)
  default     = ["subnet-0b37fd0ae1a15dba7", "subnet-0b53034010ea750c6"] # us-east-1a, us-east-1b
}

variable "vpc_route_table_id" {
  description = "Main route table ID for gateway endpoint associations"
  type        = string
  default     = "rtb-0db9fc4318f934f9b"
}

variable "dynamodb_table_name" {
  description = "DynamoDB table name for vedio/audio transcription jobs"
  type        = string
  default     = "transcribe-jobs"
}
