# the cache invalidation can be done in cloudfront console
# in order to achieve automation, lambda is introduced to complete the task
#1 to zip .py file for future terraform upload
#2 to create lambda role
#3 to create IAM policies
    #3.1 to allow connection to/from SQS
    #3.2 to allow to list/get files in s3
    #3.3 to allow to write in cloudwatch for logs
    #3.4 to allow to publish SNS topics
    #3.5 to allow to list/find s3's cloudfront distribution and create invalidation
#4 to create lambda function
#5 to setup lambda to publish through SNS
#6 to allow SQS trigger lambda (this will be done in another file)

locals {
  lambda_name                    = "${local.prefix}-lambda-cache"
  lambda_role                    = "${local.prefix}-role-lambda-cache"
  lambda_code_path               = "${path.module}/here is your local folder path "
  lambda_archive_path            = "${path.module}/here is your local folder path/cacheinvalidation.zip"
  lambda_handler                 = "invalidation.lambda_handler"
  # this is my handler, do change to your handler
  lambda_description             = "This is Lambda function to invalidate cache in cloudfront"
  lambda_runtime                 = "python3.9"
  lambda_timeout                 = 600
  lambda_concurrent_executions   = -1
  lambda_log_group               = "/aws/lambda/${local.lambda_name}"
  lambda_log_retention_in_days   = 7
  ephemeral_storage_size         =10240
  # Note: to increase lambda capacity doesnot mean to pay more
  # the lambda is charged by running time
  # the longer time the lambda runs, the more we pay
  # the more powerful/capacity the lambda is, the less time it runs.
  # so we can increase storage and memory to improve efficiency and don't need to pay more.
  # of course, all the above doesnot include the situations when we pay AWS for more lambda concurrency
  memory_size                    =3008
}

#1 below is to pack lambda function 
data "archive_file" "function_zip" {
  source_dir = local.lambda_code_path
  output_path = local.lambda_archive_path
  type = "zip"
}

#2 below is to create role for lambda function
resource "aws_iam_role" "lambda_role" {
  name="${local.lambda_role}"
  tags = {
   tag-key = "${local.lambda_role}"
  }
  assume_role_policy =<<EOF
{
  "Version":"2012-10-17",
  "Statement":[
      {
          "Action":"sts:AssumeRole",
          "Principal":{
              "Service":"lambda.amazonaws.com"
          },
          "Effect":"Allow",
          "Sid":""
      }
  ]
}
EOF
}
#3 below is to create policies 
#3.1 first to create a new policy for lambda <--> SQS
# AWS managed policies are ok only when they can provide the least priviledge
# otherwise, always create new policies based on the actual work of aws resources or users
resource "aws_iam_policy" "LambdaInteractSQS" {
  name        = "${local.prefix}-policy-Lambda-SQS"
  path        = "/"
  description = "Attached to function. it allows lambda to read/delete/send messages to SQS"
  depends_on = [
    aws_sqs_queue.example
  ]
  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "SQSconnectslambda",
            "Effect": "Allow",
            "Action": [
                "sqs:DeleteMessage",
                "sqs:ReceiveMessage",
                "sqs:SendMessage",
                "sqs:GetQueueAttributes"
            ],
            "Resource": "${aws_sqs_queue.example.arn}"
        }
    ]
})
}
#3.2 below is to generate policies: lambda <--> S3
# when lambda pick the message from SQS 
# it will check the versioning of the file

resource "aws_iam_policy" "LambdaS3" {
  name        = "${local.prefix}-policy-Lambda-S3"
  path        = "/"
  description = "Attached to function. it allows lambda to list object versions"
  depends_on = [
    aws_s3_bucket.example
  ]
  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "ListVersions",
            "Effect": "Allow",
            "Action": [
                
                "s3:ListBucket",
                "s3:ListBucketVersions"
            ],
            "Resource": [
                "${aws_s3_bucket.example.arn}/*",
                "${aws_s3_bucket.example.arn}"
            ]
        }
    ]
})
}

#3.3 to create policies: lambda --> cloudwatch log
resource "aws_iam_policy" "LambdaBasicExecutionPolicy" {
    name="${local.prefix}-policy-Lambda-CloudWatch"
    policy=<<EOF
{
    "Version":"2012-10-17",
    "Statement":[
        {
            "Effect":"Allow",
            "Action":[
                "logs:CreateLogStream",
                "logs:CreateLogGroup",
                "logs:PutLogEvents"
            ],
            "Resource":[
              "arn:aws:logs:${local.aws_region}:${local.AccountID}:log-group:${local.lambda_log_group}:*",
              "arn:aws:logs:${local.aws_region}:${local.AccountID}:log-group:${local.lambda_log_group}:log-stream:*"
            ]
        }
    ]
}
EOF
}
#3.4 to create policies: lambda --> SNS
# as for SNS, 1st stage only requires to publish email messages

resource "aws_iam_policy" "LambdaOnlyPublishSNS" {
  name        = "${local.prefix}-policy-Lambda-SNS"
  path        = "/"
  description = "Attached to lambda function. it allows lambda to publish SNS topics"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": [
                "${local.topic_arn_on_success}",
                "${local.topic_arn_on_failure}"
            ]
        }
    ]
})
}

#3.5 policy: lambda will try to find s3's cloudfront,
 # so that it could initiate the cache invalidation
resource "aws_iam_policy" "LambdaCF" {
  name        = "${local.prefix}-policy-Lambda-Cloudfront"
  path        = "/"
  description = "Attached to lambda function. it allows lambda to search for cf"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cloudfront:ListDistributions",
                "cloudfront:CreateInvalidation"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
})
}

# parent lambda to invoke child lambda
# later the website will use child lambda to do more detailed jobs 
# below is reserved for next stage
/*
resource "aws_iam_policy" "InvokeAnotherLambdaPolicy" {
  name        = "${local.prefix}-policy-InvokeAnotherLambdaPolicy"
  path        = "/"
  description = "Attached to loading function. it allows parent lambda to invoke child function"
  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": "lambda:InvokeFunction",
            "Resource": aws_lambda_function.child_function.arn
        }
    ]
})
}
*/
resource "aws_iam_role_policy_attachment" "invalidation" {
    for_each = zipmap(
    [0,1,2,3,4],
    [
        tostring(aws_iam_policy.LambdaBasicExecutionPolicy.arn),
        tostring(aws_iam_policy.LambdaS3.arn), 
        tostring(aws_iam_policy.LambdaOnlyPublishSNS.arn), 
        tostring(aws_iam_policy.LambdaInteractSQS.arn),
        tostring(aws_iam_policy.LambdaCF.arn),
        #tostring(aws_iam_policy.InvokeAnotherLambdaPolicy.arn),
    ])
  
    role       = aws_iam_role.lambda_role.name
    policy_arn = each.value
}

#4 below is to set up lambda function 
resource "aws_lambda_function" "invalidation" {
    filename                       = data.archive_file.function_zip.output_path
    function_name                  = "${local.lambda_name}"
    role                           = aws_iam_role.lambda_role.arn
    handler                        = local.lambda_handler
    runtime = local.lambda_runtime
    timeout = local.lambda_timeout
    memory_size = local.memory_size
    ephemeral_storage {
        size = local.ephemeral_storage_size
        # Min 512 MB and the Max 10240 MB
    }
    depends_on                     = [
    aws_iam_role_policy_attachment.invalidation
    ]
    source_code_hash = data.archive_file.function_zip.output_base64sha256
    reserved_concurrent_executions = local.lambda_concurrent_executions
    layers           = ["${local.AWSSDKPandas}"]

    environment {
        variables = {
        aws_region            = "${local.aws_region}"
        Account_Id            = "${local.AccountID}"
        topic_name_on_success = "${var.sns_topic_name}"
        topic_arn_on_success  = "${local.topic_arn_on_success}"
        topic_name_on_failure = "${var.sns_topic_name2}"
        topic_arn_on_failure  = "${local.topic_arn_on_failure}"
        }
    }
    publish                     = true
    tags = {
        Name                    = "${local.lambda_name}"
    }
}
#=======================================
#5 link lambda with SNS topics

resource "aws_lambda_function_event_invoke_config" "example" {
  function_name                = aws_lambda_function.invalidation.function_name
  maximum_retry_attempts       = 1

  destination_config {
    on_failure {
      destination ="${local.topic_arn_on_failure}"
    }

    on_success {
      destination ="${local.topic_arn_on_success}"

    }
  }
}
