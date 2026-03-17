output "bucket_name" {
  value = aws_s3_bucket.main.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.video_jobs.name
}

output "app_irsa_role_arn" {
  description = "Annotate the summariser-app Kubernetes service account with this ARN"
  value       = aws_iam_role.app_irsa.arn
}

output "litellm_irsa_role_arn" {
  description = "Annotate the litellm-app Kubernetes service account with this ARN"
  value       = aws_iam_role.litellm_irsa.arn
}

# §7.2: Copy these into k8s/01-secrets.yaml → bedrock-guardrail-secret
output "bedrock_guardrail_id" {
  description = "Bedrock Guardrail ID — set as guardrail-id in bedrock-guardrail-secret"
  value       = aws_bedrock_guardrail.llmgw.guardrail_id
}

output "bedrock_guardrail_version" {
  description = "Bedrock Guardrail version — set as guardrail-version in bedrock-guardrail-secret"
  value       = aws_bedrock_guardrail_version.llmgw_v1.version
}
