# Remote state backend — S3 + DynamoDB locking.
#
# Bootstrap (one-time, before terraform init):
#   aws s3api create-bucket \
#     --bucket llmgw-tfstate-409633134924 \
#     --region us-east-1
#
#   aws s3api put-bucket-versioning \
#     --bucket llmgw-tfstate-409633134924 \
#     --versioning-configuration Status=Enabled
#
#   aws s3api put-bucket-encryption \
#     --bucket llmgw-tfstate-409633134924 \
#     --server-side-encryption-configuration \
#       '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
#
#   aws s3api put-public-access-block \
#     --bucket llmgw-tfstate-409633134924 \
#     --public-access-block-configuration \
#       "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
#
#   aws dynamodb create-table \
#     --table-name llmgw-tfstate-lock \
#     --attribute-definitions AttributeName=LockID,AttributeType=S \
#     --key-schema AttributeName=LockID,KeyType=HASH \
#     --billing-mode PAY_PER_REQUEST \
#     --region us-east-1
#
# Then migrate local state:
#   terraform init -migrate-state

terraform {
  backend "s3" {
    bucket         = "llmgw-tfstate-${data.aws_caller_identity.current.account_id}"
    key            = "llmgw/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "llmgw-tfstate-lock"
  }
}
