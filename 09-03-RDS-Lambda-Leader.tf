##### This file is to create lambda for DATA ETL.
##### It's different from the file of 06-03-S3-Lambda.tf which creates Lambda for Cloudfront Cache Invalidation.

# the data loading and analysing can be done in MySQL 
# in order to achieve automation, lambda is introduced to complete the task
#### Method ####
# for AWS resources in the VPC, Data Warehouse (Redshift) or Database (Aurora) provide API
# Lambda out of VPC can connect these databases directly 
# Meanwhile , a public lambda is flexible to connect to nearly all AWS resources
# But, RDS for MySQL does not provide any API, we have to put lambda within the same VPC 

# Public lambda without VPC is easier to connect to Public services like Secrets Manager, ECR, etc
# But for security reason, Public Lambda (Parent Lambda) is not allowed to access any secret from Secrets Manager. 
# Most of the detailed work on ETL will be done by Private Lambda (Child Lambda) and ECS in the VPC using VPC endpoint.

#Leader lambda --> (VPC) --> Loading lambda
#Leader lambda --> (VPC) --> ECS

#=========================================================================================
#1 to zip .py file for future terraform upload
#2 to create lambda role
#3 to create IAM policies 
  # the leader role in the 2nd method is simple
  # it accesses AWS resources that only accept internet connections like Secret Manager
    #3.1 to allow access to CloudWatch Logs
    #3.2 to allow access to S3
    #3.3 to allow access to SNS
    #3.4 to allow access to SQS
    #3.5 to allow to invoke Child Lambda
    #3.6 to allow access to ECS
#4 to create lambda function
#5 to allow lambda invoke SNS
#6 to build resource based policy to restrice access:
  # only target SQS can trigger this lambda 

locals {
  lambda_name_leader                     = "${local.prefix}-lambda-data-mysql-leader"
  lambda_role_leader                     = "${local.prefix}-role-lambda-data-mysql-leader"
  lambda_code_path_leader                = "${path.module}/lambda/data-mysql/leader"
  lambda_archive_path_leader             = "${path.module}/lambda/data-mysql/leader/leader.zip"
  lambda_handler_leader                  = "leader.lambda_handler"
  lambda_description_leader              = "This is Lambda function to get info for private lambda"
  lambda_runtime_leader                  = "python3.10"
  lambda_timeout_leader                  = 120
  # as we use leader lambda to invoke loading lambda with response type
  # leader lambda timeout = leader lambda timeout + loading lambda timeout
  lambda_concurrent_executions_leader    = -1
  lambda_log_group_leader                = "/aws/lambda/${local.lambda_name_leader}"
  lambda_log_retention_in_days_leader    = 7
  ephemeral_storage_size_leader          = 10240
  memory_size_leader                     = 3008
  # lambda is charged by usage and time
  # setting up with the highest storage and memory for lamdba will decrease the execution time
  # setting up with the lowest storage and memory for lamdba will increase the time
  # so, the lowest setting won't save money and it causes low performance
}

#1 below is to pack lambda function 
data "archive_file" "function_zip_leader" {
  source_dir = local.lambda_code_path_leader 
  output_path = local.lambda_archive_path_leader 
  type = "zip"
}

#2 below is to create role for lambda function
resource "aws_iam_role" "role_lambda_data_mysql_leader" {
  name="${local.lambda_role_leader}"
  tags = {
   tag-key = "${local.lambda_role_leader}"
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
resource "aws_iam_policy" "LambdaBasicExecutionPolicy_leader" {
    name="${local.prefix}-policy-Lambda-leader-CloudWatch"
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
            "arn:aws:logs:${local.aws_region}:${local.AccountID}:log-group:${local.lambda_log_group_leader}:*",
            "arn:aws:logs:${local.aws_region}:${local.AccountID}:log-group:${local.lambda_log_group_leader}:log-stream:*"
          ]
      }
  ]
}
EOF
}
# 3.4 loading lambda be invoked by leader lambda out of VPC

resource "aws_iam_policy" "LeaderInvokeAnotherLambdaPolicy" {
  name        = "${local.prefix}-policy-LeaderInvokeAnotherLambdaPolicy"
  path        = "/"
  description = "Attached to leader function. it allows leader lambda to invoke loading function"
depends_on = [ aws_lambda_function.data_mysql_loading ]
  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "VisualEditor0",
        "Effect": "Allow",
        "Action": "lambda:InvokeFunction",
        "Resource": [
          aws_lambda_function.data_mysql_loading.arn
        ]
      }
    ]
})
}

resource "aws_iam_policy" "LeaderInvokeECS" {
  name        = "${local.prefix}-policy-LeaderInvokeECS"
  path        = "/"
  description = "Attached to function. it allows lambda to run ECS fargate task"
 
  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "runtask",
        "Effect": "Allow",
        "Action": [
          "ecs:RunTask"
        ]
        "Resource": [
          "${local.task_arn_without_version}"
        ]
      },
      {
        "Sid": "describetasks",
        "Effect": "Allow",
        "Action": [
          "ecs:DescribeTasks"
        ]
        "Resource": [
          "${local.task_id_for_lambda_policy}"
        ]
      },
      {
        "Sid": "passrole",
        "Effect": "Allow",
        "Action": [
          "iam:PassRole"
        ],
        "Resource": [
          aws_iam_role.ecs_task_execution_role.arn,
          aws_iam_role.ecs_task_role.arn
        ]
      }
    ]
})
}

resource "aws_iam_role_policy_attachment" "data_mysql_leader" {
  for_each = zipmap(
  [0,1,2,3,4,5],
  [
    tostring(aws_iam_policy.LambdaBasicExecutionPolicy_leader.arn),
    tostring(aws_iam_policy.LambdaS3.arn), 
    tostring(aws_iam_policy.LambdaOnlyPublishSNS.arn),
    tostring(aws_iam_policy.LambdaInteractSQS.arn),
    tostring(aws_iam_policy.LeaderInvokeAnotherLambdaPolicy.arn),
    tostring(aws_iam_policy.LeaderInvokeECS.arn)
  ])

  role       = aws_iam_role.role_lambda_data_mysql_leader.name
  policy_arn = each.value
}

#4 below is to set up lambda function 
resource "aws_lambda_function" "data_mysql_leader" {
  depends_on = [ aws_lambda_function.data_mysql_loading ]
  filename                       = data.archive_file.function_zip_leader.output_path
  function_name                  = "${local.lambda_name_leader}"
  role                           = aws_iam_role.role_lambda_data_mysql_leader.arn
  handler                        = local.lambda_handler_leader
  runtime = local.lambda_runtime_leader
  timeout = local.lambda_timeout_leader
  memory_size = local.memory_size_leader
  ephemeral_storage {
      size = local.ephemeral_storage_size_leader
      # Min 512 MB and the Max 10240 MB
  }
  source_code_hash = data.archive_file.function_zip_leader.output_base64sha256
  reserved_concurrent_executions = local.lambda_concurrent_executions_leader
  layers           = ["${local.AWSSDKPandas}"]
  environment {
    variables = {
    aws_region            = "${local.aws_region}"
    Account_Id            = "${local.AccountID}"
    topic_name_on_success = "${var.sns_topic_name}"
    topic_arn_on_success  = "${local.topic_arn_on_success}"
    topic_name_on_failure = "${var.sns_topic_name2}"
    topic_arn_on_failure  = "${local.topic_arn_on_failure}"
    backup_bucket         = var.bucket_for_backup_sourcedata
    loading_arn           = aws_lambda_function.data_mysql_loading.arn
    reporting_arn         = aws_lambda_function.data_mysql_reporting.arn
    ecs_task_arn          = tostring(aws_ecs_task_definition.example.family)
    ecs_cluster_arn       = tostring(aws_ecs_cluster.example.arn)
    ecs_service_subnets   = "${join(",", local.private_subnets)}"
    ecs_security_groups   =  aws_security_group.ecs_service.id
    ecs_container_name    = local.container_definition.0.name
    }
  }
  publish                     = true
  tags = {
      Name                    = "${local.lambda_name_leader}"
  }
}
#=======================================
#5 link lambda with SNS topics
resource "aws_lambda_function_event_invoke_config" "lambda-sns-leader" {
  function_name                = aws_lambda_function.data_mysql_leader.function_name
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

# 6 to restrict only target SQS can trigger this lambda 
# Lambda if not deployed in VPC is exposed publicly,
# we don't wish everyone can trigger our Lambda in the public
# to use resource-based policy
resource "aws_lambda_permission" "lambda_allow_sqs" {
  statement_id  = "AllowTriggerFromSQS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_mysql_leader.function_name
  principal     = "sqs.amazonaws.com"
  source_arn    = aws_sqs_queue.example.arn
  source_account = local.AccountID
}