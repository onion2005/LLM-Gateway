locals {
  lambda_zip_dir = "${path.module}/.lambda_zips"
}

# ─── start-transcribe ─────────────────────────────────────────────────────────

data "archive_file" "start_transcribe" {
  type        = "zip"
  output_path = "${local.lambda_zip_dir}/start_transcribe.zip"

  source {
    filename = "handler.py"
    content  = <<-EOT
      import boto3
      import os
      import time
      import urllib.parse

      def handler(event, context):
          record  = event["Records"][0]
          bucket  = record["s3"]["bucket"]["name"]
          key     = urllib.parse.unquote_plus(record["s3"]["object"]["key"])

          # Derive a stable job name from the S3 key + timestamp
          safe_key = key.replace("/", "-").replace(".", "-").replace(" ", "-")
          job_name = f"{safe_key}-{int(time.time())}"[:200]  # Transcribe limit

          # Detect media format from extension
          ext = key.rsplit(".", 1)[-1].lower()
          fmt_map = {"mp4": "mp4", "mp3": "mp3", "wav": "wav",
                     "flac": "flac", "ogg": "ogg", "amr": "amr", "webm": "webm"}
          media_format = fmt_map.get(ext, "mp4")

          transcribe = boto3.client("transcribe")
          transcribe.start_transcription_job(
              TranscriptionJobName=job_name,
              Media={"MediaFileUri": f"s3://{bucket}/{key}"},
              MediaFormat=media_format,
              LanguageCode="zh-CN",
              OutputBucketName=bucket,
              OutputKey=f"transcripts/{job_name}.json",
          )

          dynamodb = boto3.resource("dynamodb")
          table = dynamodb.Table(os.environ["DYNAMODB_TABLE"])
          table.put_item(Item={
              "job_id":            job_name,
              "status":            "IN_PROGRESS",
              "source_s3_key":     key,
              "transcript_s3_key": f"transcripts/{job_name}.json",
              "created_at":        int(time.time()),
          })

          print(f"Started transcription job: {job_name}")
          return {"job_id": job_name}
    EOT
  }
}

resource "aws_lambda_function" "start_transcribe" {
  function_name    = "start-transcribe"
  role             = aws_iam_role.lambda_start_transcribe.arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.start_transcribe.output_path
  source_code_hash = data.archive_file.start_transcribe.output_base64sha256
  timeout          = 30
  kms_key_arn      = aws_kms_key.main.arn

  vpc_config {
    subnet_ids         = var.lambda_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DYNAMODB_TABLE = var.dynamodb_table_name
    }
  }
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start_transcribe.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.main.arn
  source_account = data.aws_caller_identity.current.account_id
}

# ─── notify ───────────────────────────────────────────────────────────────────

data "archive_file" "notify" {
  type        = "zip"
  output_path = "${local.lambda_zip_dir}/notify.zip"

  source {
    filename = "handler.py"
    content  = <<-EOT
      import boto3
      import os
      import time

      def handler(event, context):
          detail   = event["detail"]
          job_name = detail["TranscriptionJobName"]
          status   = detail["TranscriptionJobStatus"]  # COMPLETED or FAILED

          dynamodb = boto3.resource("dynamodb")
          table = dynamodb.Table(os.environ["DYNAMODB_TABLE"])
          table.update_item(
              Key={"job_id": job_name},
              UpdateExpression="SET #s = :s, updated_at = :t",
              ExpressionAttributeNames={"#s": "status"},
              ExpressionAttributeValues={":s": status, ":t": int(time.time())},
          )

          print(f"Job {job_name} → {status}")
          return {"job_id": job_name, "status": status}
    EOT
  }
}

resource "aws_lambda_function" "notify" {
  function_name    = "transcribe-notify"
  role             = aws_iam_role.lambda_notify.arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.notify.output_path
  source_code_hash = data.archive_file.notify.output_base64sha256
  timeout          = 15
  kms_key_arn      = aws_kms_key.main.arn

  vpc_config {
    subnet_ids         = var.lambda_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DYNAMODB_TABLE = var.dynamodb_table_name
    }
  }
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notify.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.transcribe_complete.arn
}
