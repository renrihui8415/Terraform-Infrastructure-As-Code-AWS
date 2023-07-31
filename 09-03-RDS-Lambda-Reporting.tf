# After report data is calculated and saved in the tables using stored procedures in MySQL,
# reporting lambda will be invoked and export the table into s3 bucket

#Leader Lambda --> (VPC) --> Reporting Lambda -(CLI)-> MySQL --> S3

#=========================================================================================

#2 to create lambda role
#3 to create IAM policies
    #3.1 to allow to create files in s3
    #3.2 to allow to write in cloudwatch for logs
    #3.3 to allow to publish SNS topics
    #3.4 to allow access to VPC
    #3.5 to allow to read specific secret from Secrets Manager
#4 to create lambda function
#5 to allow lambda publish SNS
#6 to create an 'empty' security group for lambda within a VPC
  # it just serves as a placeholder, there is no rules required for this SG 
#7 to create s3 endpoint for lamba in the VPC
  #7.1 to create gateway s3 endpoint
  #7.2 to create interface secrets endpoint
    #7.2.1 to create SG for endpoint and allows Lambda <--> Endpoint 
    #7.2.2 to create interface secrets endpoint

locals {
  lambda_name_reporting                    = "${local.prefix}-lambda-data-mysql-reporting"
  lambda_role_reporting                    = "${local.prefix}-role-lambda-data-mysql-reporting"
  lambda_code_path_reporting               = "${path.module}/lambda/data-mysql/reporting"
  lambda_archive_path_reporting            = "${path.module}/lambda/data-mysql/reporting/reporting.zip"
  lambda_handler_reporting                 = "reporting.handler"
  lambda_description_reporting             = "This is Lambda function to export data in RDS MySQL to s3"
  lambda_runtime_reporting                 = "python3.10"
  lambda_timeout_reporting                 = 60
  lambda_concurrent_executions_reporting   = -1
  lambda_log_group_reporting               = "/aws/lambda/${local.lambda_name_reporting}"
  lambda_log_retention_in_days_reporting   = 7
  ephemeral_storage_size_reporting         =10240
  memory_size_reporting                    =3008
}

#2 below is to create role for lambda function
resource "aws_iam_role" "role_lambda_data_mysql_reporting" {
  name="${local.lambda_role_reporting}"
  tags = {
   tag-key = "${local.lambda_role_reporting}"
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
#3.1 below is to generate policies: lambda <--> S3
# lambda is allowed to putObject in s3

resource "aws_iam_policy" "ReportingLambdaS3" {
  name        = "${local.prefix}-policy-Reporting-Lambda-S3"
  path        = "/"
  description = "Attached to function. it allows lambda to create object versions"
  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": [
                "s3:PutObject"
            ],
            "Resource": [
                "${var.bucket_arn_for_backup_sourcedata}",
                "${var.bucket_arn_for_backup_sourcedata}/*"
            ]
        }
    ]
})
}

#3.2 to create policies: lambda --> cloudwatch log
resource "aws_iam_policy" "LambdaBasicExecutionPolicy_reporting" {
    name="${local.prefix}-policy-Lambda-reporting-CloudWatch"
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
              "arn:aws:logs:${local.aws_region}:${local.AccountID}:log-group:${local.lambda_log_group_reporting}:*",
              "arn:aws:logs:${local.aws_region}:${local.AccountID}:log-group:${local.lambda_log_group_reporting}:log-stream:*"
            ]
        }
    ]
}
EOF
}

# 3.4 lambda to access VPC

locals {
  #subnet_arns=[
    #for subnet_id in aws_db_subnet_group.rds.subnet_ids:
    #"arn:aws:ec2:${local.aws_region}:${local.AccountID}:subnet/${subnet_id}"
  #]
  #eni_arns="arn:aws:ec2:${local.aws_region}:${local.AccountID}:network-interface/*"
  security_group_arn_reporting="arn:aws:ec2:${local.aws_region}:${local.AccountID}:security-group/${aws_security_group.reporting_lambda_in_vpc.id}"
  #security_group_arn_delete="arn:aws:ec2:${local.aws_region}:${local.AccountID}:*/*"
}
locals {
  string_for_policy_reporting=concat(local.subnet_arns,[local.eni_arns],[local.security_group_arn_reporting])
}
#output "string_for_policy_quotes" {
  #value = local.string_for_policy
#}
resource "aws_iam_policy" "ReportingLambdaAccessVPC" {
  name        = "${local.prefix}-policy-ReportingLambdaAccessVPC"
  path        = "/"
  description = "Attached to reporting function. it allows reporting lambda to access VPC and the resources within"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "describeEni",
        "Effect": "Allow",
        "Action": [
          "ec2:DescribeNetworkInterfaces"
        ]
        "Resource": ["*"]      
      },
      {
        "Sid": "createEni",
        "Effect": "Allow",
        "Action": [
          "ec2:CreateNetworkInterface"
        ]
        "Resource": local.string_for_policy_reporting      
      },
      {
        "Sid": "deleteEni",
        "Effect": "Allow",
        "Action": [
          "ec2:DeleteNetworkInterface"
        ]
        "Resource": [
          local.security_group_arn_delete
        ]     
      }
    ]
})
}

#3.6 to create policy for lambda to read one specific secret from secret manager
# important! please double check if lambda can only read the credentials we wish it to read
# do not assign lambda more permissions than its job
# otherwise lambda can read all secrets in aws account... 
resource "aws_iam_policy" "ReportingLambdaReadsSecret" {
  name        = "${local.prefix}-policy-ReportingLambdaReadsSecret"
  path        = "/"
  description = "Attached to function. it allows lambda to get secret"
 
  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
              "secretsmanager:GetSecretValue"
            ],
            "Resource": [
              "${local.mysql-creds-db-maintanance-arn}"
            ]
        }
    ]
})
}
resource "aws_iam_role_policy_attachment" "data_mysql_reporting" {
  for_each = zipmap(
  [0,1,2,3,4],
  [
    tostring(aws_iam_policy.LambdaBasicExecutionPolicy_reporting.arn),
    tostring(aws_iam_policy.ReportingLambdaS3.arn), 
    tostring(aws_iam_policy.LambdaOnlyPublishSNS.arn), 
    tostring(aws_iam_policy.ReportingLambdaAccessVPC.arn),
    tostring(aws_iam_policy.ReportingLambdaReadsSecret.arn)
  ])

  role       = aws_iam_role.role_lambda_data_mysql_reporting.name
  policy_arn = each.value
}

#4 below is to set up lambda function 
resource "aws_lambda_function" "data_mysql_reporting" {
  function_name                  = "${local.lambda_name_reporting}"
  role                           = aws_iam_role.role_lambda_data_mysql_reporting.arn
  image_uri                      = "${local.AccountID}.dkr.ecr.${local.aws_region}.amazonaws.com/${local.lambda_repo_name}:latest"
  package_type                   = "Image"
  timeout                        = local.lambda_timeout_reporting
  memory_size                    = local.memory_size_reporting
  ephemeral_storage {
    size                         = local.ephemeral_storage_size_reporting
    # Min 512 MB and the Max 10240 MB
  }
  reserved_concurrent_executions = local.lambda_concurrent_executions_reporting
  image_config {
    # use this to point this lambda to the right handler
    # within the same image
    #if only to serve a single-handler lambda .py file
    command = ["reporting.handler"]
  }
  environment {
    variables = {
      aws_region            = "${local.aws_region}"
      mysql_database        = aws_db_instance.mysql.db_name
      mysql_host            = aws_db_instance.mysql.endpoint
      backup_bucket         = var.bucket_for_backup_sourcedata
      secret_name           = data.aws_secretsmanager_secret_version.mysql-creds-db-maintanance.secret_id
    }
  }
  vpc_config {
    security_group_ids = [aws_security_group.reporting_lambda_in_vpc.id]
    subnet_ids = aws_db_subnet_group.rds.subnet_ids
  }
  publish                     = true
  tags = {
      Name                    = "${local.lambda_name_reporting}"
  }
}
#=======================================
#5 link lambda with SNS topics
resource "aws_lambda_function_event_invoke_config" "lambda-sns-reporting" {
  function_name                = aws_lambda_function.data_mysql_reporting.function_name
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

#6 below is to create SG for lambda within in vpc
resource "aws_security_group" "reporting_lambda_in_vpc" {
  name        = "${local.prefix}-sg-lambda-reporting-in-vpc"
  description = "Place holder "
  vpc_id      = aws_vpc.web_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.prefix}-sg-lambda-reporting-in-vpc"
  }
}
# make sure rds SG allows lambda SG
resource "aws_security_group_rule" "reporting_lambda_to_rds" {
  type            = "ingress"
  from_port       = 3306
  to_port         = 3306
  protocol        = "tcp"
  #=====================================================
  source_security_group_id = aws_security_group.reporting_lambda_in_vpc.id
  #=====================================================
  security_group_id = aws_security_group.rds.id

}
# make sure rds SG allows lambda SG
resource "aws_security_group_rule" "rds_to_lambda_reporting" {
  type            = "ingress"
  from_port       = 3306
  to_port         = 3306
  protocol        = "tcp"
  #=====================================================
  source_security_group_id = aws_security_group.rds.id
  #=====================================================
  security_group_id = aws_security_group.reporting_lambda_in_vpc.id

}

resource "aws_security_group_rule" "reporting_lambda_to_vpc_endpoints" {
  type            = "ingress"
  from_port       = 443
  to_port         = 443
  protocol        = "tcp"
  #cidr_blocks = [aws_vpc.web_vpc.cidr_block]
  source_security_group_id = aws_security_group.reporting_lambda_in_vpc.id

  security_group_id = aws_security_group.vpc_endpoints_ecr_secret_logs.id 
}

#7 Reporting Lambda applies the same VPC Endpoints with Loading Lambda