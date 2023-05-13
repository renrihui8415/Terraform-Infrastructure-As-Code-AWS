# Cloudfront cache invalidation:
# the solution in this project is to use lambda to invalidate the files when they are uploaded into s3
# S3 --> SQS --> Lambda 
# the combination of "s3-sqs-lamda" is a quite efficient, secure and powerful tool in many situations,
# especially for automation. 
# it helped me a lot in my previous object.

#1 to create standard SQS 
#2 to create IAM policy for SQS 
  # the policy will restrictly assign which s3 bucket can push message to which SQS
#3 to create lambda event source, SQS --> lambda
#4 to create Dead Letter Queue
  # to prevent error files or unexpected problems which can't be solved by lambda
  # use Dead Letter Queue to catch those messages
#5 to configure cloudwatch to monitor dead letter queue (another file)

#============================================
#1 "s3-->SQS-->lambda"
resource "aws_sqs_queue" "example" {
  name = "${local.prefix}-${var.sqs_name}"
  visibility_timeout_seconds =600
  fifo_queue =false
  sqs_managed_sse_enabled =true
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.sqs-lambda-dlq.arn
    #maxReceiveCount     = 5
    # retries times before the dead message go to dead letter queue
    # below is set to 1 for testing
    maxReceiveCount     = 1
  })
  depends_on = [
    aws_s3_bucket.example,
    aws_sqs_queue.sqs-lambda-dlq
  ]
  tags = {
    Name  = "${local.prefix}-${var.sqs_name}"
  }

}
#============================================
#2 create policy for SQS 
#so that s3 can push messages of event to SQS 
resource "aws_sqs_queue_policy" "sqs_policy" {
  queue_url = aws_sqs_queue.example.id
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "example-ID",
  "Statement": [
    {
      "Sid": "example-statement-ID",
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": "SQS:SendMessage",
      "Resource": "${aws_sqs_queue.example.arn}",
      "Condition": {
        "StringEquals": {
          "aws:SourceAccount": "${local.AccountID}"
        },
        "ArnLike": {
          "aws:SourceArn": "${aws_s3_bucket.example.arn}"
        }
      }
    }
  ]
}
POLICY
}
#=======================================
#3  create event source for lambda
# "SQS-->lambda"
# so that lambda can be triggered by standard queue
resource "aws_lambda_event_source_mapping" "event_source_mapping" {
  event_source_arn = aws_sqs_queue.example.arn
  enabled          = true
  function_name    = aws_lambda_function.invalidation.arn
  batch_size       = 5
  #if we let lambda to process one sqs message per batch per time
  # below "ReportBatchItemFailures" won't be applied
  function_response_types = ["ReportBatchItemFailures"]
  maximum_batching_window_in_seconds=0
  #maximum_batching_window_in_seconds decides how long sqs needs to collect info
  #before invoking lambda.amazon_managed_kafka_event_source_config {
  # either maximum_batching_window_in_seconds expires or batch_size being met,
  # the sqs will push messages to lambda
  # scaling_config, Only available for SQS queues-->Kafka

}

#4 to create dead letter queue
resource "aws_sqs_queue" "sqs-lambda-dlq" {
  name = "${local.prefix}-${var.dlq_name}"
  receive_wait_time_seconds = 0
  #lambda push the message and stop to proceed immediately
  message_retention_seconds = 3600
  #3600s, 1 hour is enough for the dead message to be in the queue
  #as the cloudwatch will evaluate and test to see if
  # the message stays in the dead queue for 1 minutes
  # and push the alert to SNS
  tags = {
    Name  = "${local.prefix}-${var.dlq_name}"
  }
}


