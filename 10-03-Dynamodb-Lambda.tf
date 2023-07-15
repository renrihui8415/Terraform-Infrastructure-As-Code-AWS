# use Dynamodb to store data 
#s3 --> Loading Lambda --> Dynamodb
#=========================================================================================
#1 to zip .py file for future terraform upload
#2 to create lambda role
#3 to create IAM policies 
  #3.1 to allow access to Dynamodb
  #3.2 to allow access to s3
  #3.3 to allow access to CloudWatch Logs
#4 to create lambda function
#5 to allow lambda invoke SNS

locals {
  lambda_name_loading_dynamodb                     = "${local.prefix}-lambda-data-dynamodb-loading"
  lambda_role_loading_dynamodb                     = "${local.prefix}-role-lambda-data-dynamodb-loading"
  lambda_code_path_loading_dynamodb                = "${path.module}/lambda/data-dynamodb/loading"
  lambda_archive_path_loading_dynamodb             = "${path.module}/lambda/data-dynamodb/loading/loading.zip"
  lambda_handler_loading_dynamodb                  = "loading.lambda_handler"
  lambda_description_loading_dynamodb              = "This is Lambda function to load from s3 to dynamodb"
  lambda_runtime_loading_dynamodb                  = "python3.10"
  lambda_timeout_loading_dynamodb                  = 600
  # using lambda to load data is extremely slow, 
  # i only use lambda to ETL when the dataset is quite small
  lambda_concurrent_executions_loading_dynamodb    = -1
  lambda_log_group_loading_dynamodb                = "/aws/lambda/${local.lambda_name_loading_dynamodb}"
  # a specified log group for import table feature is needed for loading data to dynamodb
  dynamodb_log_group_import_table                  = "/aws-dynamodb/imports"
  lambda_log_retention_in_days_loading_dynamodb    = 7
  ephemeral_storage_size_loading_dynamodb          = 10240
  memory_size_loading_dynamodb                     = 3008
}

#1 below is to pack lambda function 
data "archive_file" "function_zip_loading_dynamodb" {
  source_dir = local.lambda_code_path_loading_dynamodb 
  output_path = local.lambda_archive_path_loading_dynamodb 
  type = "zip"
}

#2 below is to create role for lambda function
resource "aws_iam_role" "role_lambda_data_dynamodb_loading" {
  name="${local.lambda_role_loading_dynamodb}"
  tags = {
   tag-key = "${local.lambda_role_loading_dynamodb}"
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
    aws_sqs_queue.data_analysis
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
        "Resource": "${aws_sqs_queue.data_analysis.arn}"
      }
    ]
})
}
#3.2 below is to generate policies: lambda <--> S3
# when lambda pick the message from SQS 
# it will check the s3 file
# leader lambda accesses the upload bucket for checking and backup bucket for backup
# while loading lambda access upload bucket loading and backup bucket for splitting and loading

resource "aws_iam_policy" "LambdaS3" {
  name        = "${local.prefix}-policy-Lambda-S3"
  path        = "/"
  description = "Attached to function. it allows lambda to access s3"
  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:ListBucket",
                "s3:DeleteObject"
            ],
            "Resource": [
                "${aws_s3_bucket.data_analysis.arn}/*",
                "${aws_s3_bucket.data_analysis.arn}"
            ]
        },
        {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:ListBucket",
                "s3:DeleteObject"
            ],
            "Resource": [
                "${var.bucket_arn_for_backup_sourcedata}",
                "${var.bucket_arn_for_backup_sourcedata}/*"
            ]
        }
    ]
})
}
#3.3 to create policies: lambda --> cloudwatch log
resource "aws_iam_policy" "LambdaBasicExecutionPolicy_loading_dynamodb" {
    name="${local.prefix}-policy-Lambda-loading-dynamodb-CloudWatch"
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
            "arn:aws:logs:${local.aws_region}:${local.AccountID}:log-group:${local.lambda_log_group_loading_dynamodb}:*",
            "arn:aws:logs:${local.aws_region}:${local.AccountID}:log-group:${local.lambda_log_group_loading_dynamodb}:log-stream:*"          ]
      },
      {
          "Effect":"Allow",
          "Action":[
              "logs:CreateLogStream",
              "logs:CreateLogGroup",
              "logs:PutLogEvents",
              "logs:DescribeLogGroups",
              "logs:PutRetentionPolicy",
              "logs:DescribeLogStreams"
          ],
          "Resource":[
            "arn:aws:logs:${local.aws_region}:${local.AccountID}:log-group:${local.dynamodb_log_group_import_table}:log-stream:*",
            "arn:aws:logs:${local.aws_region}:${local.AccountID}:log-group::log-stream:*"

          ]
      }
  ]
}
EOF
}

#3.5 to access Dynamodb table
resource "aws_iam_policy" "accessDynamodb" {
  name        = "${local.prefix}-policy-accessDynamodb"
  path        = "/"
  description = "Attached to loading function. it allows lambda to access Dynamodb"
  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DynamoDBTableAccess",
            "Effect": "Allow",
            "Action": [
              "dynamodb:ImportTable",
              "dynamodb:ListTables",
              "dynamodb:BatchGetItem",
              "dynamodb:BatchWriteItem",
              "dynamodb:ConditionCheckItem",
              "dynamodb:PutItem",
              "dynamodb:DescribeTable",
              "dynamodb:DeleteItem",
              "dynamodb:GetItem",
              "dynamodb:Scan",
              "dynamodb:Query",
              "dynamodb:UpdateItem",
              "dynamodb:DeleteTable"
            ],
            "Resource": [
              "arn:aws:dynamodb:${local.aws_region}:${local.AccountID}:table/${local.dynamodb_table_name}*",
              "arn:aws:dynamodb:${local.aws_region}:${local.AccountID}:table/*"
            ]
        }
    ]
})
}

#3.6 lambda publish SNS topics
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
resource "aws_iam_role_policy_attachment" "lambda_loading_data_dynamodb" {
  for_each = zipmap(
  [0,1,2,3,4],
  [
    tostring(aws_iam_policy.LambdaBasicExecutionPolicy_loading_dynamodb.arn),
    tostring(aws_iam_policy.LambdaS3.arn), 
    tostring(aws_iam_policy.LambdaOnlyPublishSNS.arn),
    tostring(aws_iam_policy.LambdaInteractSQS.arn),
    tostring(aws_iam_policy.accessDynamodb.arn)
  ])

  role       = aws_iam_role.role_lambda_data_dynamodb_loading.name
  policy_arn = each.value
}

#4 below is to set up lambda function 
resource "aws_lambda_function" "data_dynamodb_loading" {

  filename                       = data.archive_file.function_zip_loading_dynamodb.output_path
  function_name                  = "${local.lambda_name_loading_dynamodb}"
  role                           = aws_iam_role.role_lambda_data_dynamodb_loading.arn
  handler                        = local.lambda_handler_loading_dynamodb
  runtime = local.lambda_runtime_loading_dynamodb
  timeout = local.lambda_timeout_loading_dynamodb
  memory_size = local.memory_size_loading_dynamodb
  ephemeral_storage {
      size = local.ephemeral_storage_size_loading_dynamodb
      # Min 512 MB and the Max 10240 MB
  }
  source_code_hash = data.archive_file.function_zip_loading_dynamodb.output_base64sha256
  reserved_concurrent_executions = local.lambda_concurrent_executions_loading_dynamodb
  layers           = ["${local.AWSSDKPandas}"]
  #arn:aws:lambda:us-east-1:336392948345:layer:AWSSDKPandas-Python39:2
  environment {
    variables = {
    aws_region            = "${local.aws_region}"
    Account_Id            = "${local.AccountID}"
    topic_name_on_success = "${var.sns_topic_name}"
    topic_arn_on_success  = "${local.topic_arn_on_success}"
    topic_name_on_failure = "${var.sns_topic_name2}"
    topic_arn_on_failure  = "${local.topic_arn_on_failure}"
    backup_bucket         = var.bucket_for_backup_sourcedata
    }
  }
  publish                     = true
  tags = {
    Name                    = "${local.lambda_name_loading_dynamodb}"
  }
}
#=======================================
#5 link lambda with SNS topics
resource "aws_lambda_function_event_invoke_config" "lambda-sns-loading" {
  function_name                = aws_lambda_function.data_dynamodb_loading.function_name
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

