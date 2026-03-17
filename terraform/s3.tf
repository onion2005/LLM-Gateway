resource "aws_s3_bucket" "main" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
    bucket_key_enabled = true # reduces KMS API call costs
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    id     = "expire-videos"
    status = "Enabled"
    filter { prefix = "videos/" }
    expiration { days = 7 }
  }

  rule {
    id     = "expire-audio"
    status = "Enabled"
    filter { prefix = "audio/" }
    expiration { days = 3 }
  }
}

# Trigger start-transcribe Lambda on any object created under videos/
resource "aws_s3_bucket_notification" "video_upload" {
  bucket = aws_s3_bucket.main.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.start_transcribe.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "videos/"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}
