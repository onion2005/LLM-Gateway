resource "aws_cloudwatch_event_rule" "transcribe_complete" {
  name        = "transcribe-job-complete"
  description = "Fires when an Amazon Transcribe job reaches COMPLETED or FAILED"

  event_pattern = jsonencode({
    source      = ["aws.transcribe"]
    detail-type = ["Transcribe Job State Change"]
    detail = {
      TranscriptionJobStatus = ["COMPLETED", "FAILED"]
    }
  })
}

resource "aws_cloudwatch_event_target" "notify_lambda" {
  rule = aws_cloudwatch_event_rule.transcribe_complete.name
  arn  = aws_lambda_function.notify.arn
}
