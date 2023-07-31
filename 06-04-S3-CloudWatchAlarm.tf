locals {
  alarm_arn=join(":",["arn:aws:cloudwatch","${local.aws_region}","${local.AccountID}","${aws_cloudwatch_metric_alarm.deadletter.alarm_name}"])
}
#============================================
#1 to create cloudwatch-alarm to monitor dead letter queue
#============================================

#1  "dead letter queue --> cloud watch"
resource "aws_cloudwatch_metric_alarm" "example" {
  alarm_name          = "${local.prefix}-cloudwatchalarm-DeadLetter"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  #one evaluation period will generate one datapoint
  #datapoints_to_alarm =1
  #one datapoint's result determines if an alert is sent
  metric_name         = "ApproximateNumberOfMessagesVisible"
  #"number of message sent" is not available for deadletter queue
  namespace           = "AWS/SQS"
  period              = "60"
  #mimumum 60 seconds-- 
  #when the dead queue is holding more than 0 messages in the period of 60s
  #we will be alerted
  statistic           = "Sum"
  threshold           = "0"
  insufficient_data_actions = []
  alarm_actions = ["${local.topic_arn_on_dlq}"]
  dimensions= {
    QueueName = "${aws_sqs_queue.sqs-lambda-dlq.name}"
  }

  alarm_description = "Messages delivered to deadletter queue"

}
