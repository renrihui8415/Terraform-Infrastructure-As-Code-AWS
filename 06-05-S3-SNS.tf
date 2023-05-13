# As services like SNS requires user confirmation with email subscription
# terraform won't be able to delete the topics and subscriptions when 
# "terraform destroy"
# therefore, below is meant to be executed for once

# below is to create SNS topics 
resource "null_resource" "create_sns_topics" {
  count       = "${length(local.sns_topics_name)}"

  triggers = {
    region        = local.aws_region
    name           = "${local.sns_topics_name[count.index]}"
    tag            = var.sns_subscription_protocol
  }

  provisioner "local-exec" {
    command   = "aws sns create-topic --name ${self.triggers.name} --region ${self.triggers.region}  --tags Key=Name,Value=${self.triggers.name} "
  }
}
# below is to subscribe SNS topics
resource "null_resource" "subscribe_sns_topics" {
  count       = "${length(local.sns_topics_arn)}"
  depends_on = [ 
    null_resource.create_sns_topics
   ]
  triggers = {
    region        = local.aws_region
    arn           = "${local.sns_topics_arn[count.index]}"
    protocol      = var.sns_subscription_protocol
    email_address = var.sns_subscription_email_address_list
    }

  provisioner "local-exec" {
    command   = "aws sns subscribe --topic-arn ${self.triggers.arn} --region ${self.triggers.region} --protocol ${self.triggers.protocol} --notification-endpoint ${self.triggers.email_address}"
  }
}
output "topic_arns" {
  value=local.sns_topics_arn
}
