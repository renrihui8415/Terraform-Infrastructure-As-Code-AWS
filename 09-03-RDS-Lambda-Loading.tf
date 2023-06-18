##### This file is to create lambda for DATA ETL.
##### It's different from the file of 06-03-s3-lambda. It creates lambda for Cloudfront Cache Invalidation.

# the data loading and analysing can be done in MySQL Workbench
# in order to achieve automation, lambda is introduced to complete the task
#### Method ####
# for AWS resources in the VPC, Data Warehouse or Database (Redshift, Aurora) provide API
# lambda doesn't need to go within VPC to connect these databases
# meanwhile , a public lambda is flexible to connect to nearly all AWS resources
# But, RDS for MySQL does not provide any API, we have to put lambda within the same VPC 
# with MySQL and can therefore keep MySQL from being public accessible.

# Lambda within VPC needs endpoint if it fetches from Secrets Manager
# Leader lambda without VPC is easier to connect to services like Secrets Manager, CloudWatch,
# but for security reason, VPC endpoint is applied, and only resources in the VPC (child lambda and ECS)
# can have sensitive info like username and password

#Leader lambda --> (VPC) --> Loading lambda
#Leader lambda --> (VPC) --> ECS

#=========================================================================================
#1 to zip .py file for future terraform upload
#2 to create lambda role
#3 to create IAM policies
    #3.1 to allow connection to/from SQS
    #3.2 to allow to list/get files in s3
    #3.3 to allow to write in cloudwatch for logs
    #3.4 to allow to publish SNS topics
#4 to create lambda function
#5 to allow lambda invoke SNS
#6 to create an 'empty' security group for lambda within a VPC
  # it just serves as a placeholder, there is no rules required for this SG 
#7 to create s3 and secret endpoints for lamba in the VPC
  #7.1 to create gateway s3 endpoint
  #7.2 to create interface secrets endpoint
    #7.2.1 to create SG for endpoint and allows Lambda <--> Endpoint 
    #7.2.2 to create interface secrets endpoint
locals {
  lambda_name_loading                    = "${local.prefix}-lambda-data-mysql-loading"
  lambda_role_loading                    = "${local.prefix}-role-lambda-data-mysql-loading"
  lambda_code_path_loading               = "${path.module}/lambda/data-mysql/loading"
  lambda_archive_path_loading            = "${path.module}/lambda/data-mysql/loading/loading.zip"
  lambda_handler_loading                 = "loading.lambda_handler"
  lambda_description_loading             = "This is Lambda function to load and analyse data in RDS MySQL"
  lambda_runtime_loading                 = "python3.10"
  lambda_timeout_loading                 = 60
  lambda_concurrent_executions_loading   = -1
  lambda_log_group_loading               = "/aws/lambda/${local.lambda_name_loading}"
  lambda_log_retention_in_days_loading   = 7
  ephemeral_storage_size_loading         =10240
  memory_size_loading                    =3008
}

#1 below is to pack lambda function 
data "archive_file" "function_zip_loading" {
  source_dir = local.lambda_code_path_loading
  output_path = local.lambda_archive_path_loading
  type = "zip"
}

#2 below is to create role for lambda function
resource "aws_iam_role" "role_lambda_data_mysql_loading" {
  name="${local.lambda_role_loading}"
  tags = {
   tag-key = "${local.lambda_role_loading}"
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
# the policies shared between parent and child lambda, are defined in parent lambda file
#3.1 to create policies: lambda --> cloudwatch log
resource "aws_iam_policy" "LambdaBasicExecutionPolicy_loading" {
    name="${local.prefix}-policy-Lambda-loading-CloudWatch"
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
              "arn:aws:logs:${local.aws_region}:${local.AccountID}:log-group:${local.lambda_log_group_loading}:*",
              "arn:aws:logs:${local.aws_region}:${local.AccountID}:log-group:${local.lambda_log_group_loading}:log-stream:*"
            ]
        }
    ]
}
EOF
}
#3.2 to create policies: lambda --> SNS
# as for SNS, 1st stage only requires to publish email messages
# later, when the website becomes popular, may use SNS --> SQS --> lambda 
# faned out 

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
# 3.3 lambda to access VPC
# To access private resources within a VPC, Lambda needs a VPC network endpoint. 
# Thus, it needs permission to create a Elastic Network Interface (ENI) in your VPC.
# use terraform to find the current ENIs

locals {
  subnet_arns=[
    for subnet_id in aws_db_subnet_group.rds.subnet_ids:
    "arn:aws:ec2:${local.aws_region}:${local.AccountID}:subnet/${subnet_id}"
  ]
  eni_arns="arn:aws:ec2:${local.aws_region}:${local.AccountID}:network-interface/*"
  security_group_arn="arn:aws:ec2:${local.aws_region}:${local.AccountID}:security-group/${aws_security_group.lambda_in_vpc.id}"
  security_group_arn_delete="arn:aws:ec2:${local.aws_region}:${local.AccountID}:*/*"
}
locals {
  string_for_policy=concat(local.subnet_arns,[local.eni_arns],[local.security_group_arn])
}
resource "aws_iam_policy" "AccessVPC" {
  name        = "${local.prefix}-policy-AccessVPC"
  path        = "/"
  description = "Attached to loading function. it allows loading lambda to access VPC and the resources within"

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
        "Resource": local.string_for_policy      
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
#3.4 lambda to access rds
# according to AWS official website, there is no need to create policy for lambda to access rds
# https://docs.aws.amazon.com/lambda/latest/dg/services-rds-tutorial.html

#3.5 to create policy for lambda to read one specific secret from secret manager
# important! please double check if lambda can only read the credentials we wish it to read
# do not assign lambda more permissions than its job
# otherwise lambda can read all secrets in aws account... 
resource "aws_iam_policy" "LambdaReadsSecret" {
  name        = "${local.prefix}-policy-LambdaReadsSecret"
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
resource "aws_iam_role_policy_attachment" "data_mysql_loading" {
  for_each = zipmap(
  [0,1,2,3,4],
  [
    tostring(aws_iam_policy.LambdaBasicExecutionPolicy_loading.arn),
    tostring(aws_iam_policy.LambdaS3.arn), 
    tostring(aws_iam_policy.LambdaOnlyPublishSNS.arn), 
    tostring(aws_iam_policy.AccessVPC.arn),
    tostring(aws_iam_policy.LambdaReadsSecret.arn)
  ])

  role       = aws_iam_role.role_lambda_data_mysql_loading.name
  policy_arn = each.value
}

#4 below is to set up lambda function 
resource "aws_lambda_function" "data_mysql_loading" {
  filename                       = data.archive_file.function_zip_loading.output_path
  function_name                  = "${local.lambda_name_loading}"
  role                           = aws_iam_role.role_lambda_data_mysql_loading.arn
  handler                        = local.lambda_handler_loading
  runtime = local.lambda_runtime_loading
  timeout = local.lambda_timeout_loading
  memory_size = local.memory_size_loading
  ephemeral_storage {
      size = local.ephemeral_storage_size_loading
      # Min 512 MB and the Max 10240 MB
  }
  source_code_hash = data.archive_file.function_zip_loading.output_base64sha256
  reserved_concurrent_executions = local.lambda_concurrent_executions_loading
  layers           = ["${local.AWSSDKPandas}"]
  #eg arn:aws:lambda:us-east-1:336392948345:layer:AWSSDKPandas-Python310:2
  environment {
    variables = {
    aws_region            = "${local.aws_region}"
    Account_Id            = "${local.AccountID}"
    topic_name_on_success = "${var.sns_topic_name}"
    topic_arn_on_success  = "${local.topic_arn_on_success}"
    topic_name_on_failure = "${var.sns_topic_name2}"
    topic_arn_on_failure  = "${local.topic_arn_on_failure}"
    mysql_database        = aws_db_instance.mysql.db_name
    mysql_host            = aws_db_instance.mysql.endpoint
    backup_bucket         = var.bucket_for_backup_sourcedata
    secret_name           = data.aws_secretsmanager_secret_version.mysql-creds-db-maintanance.secret_id

    }
  }
  vpc_config {
    security_group_ids = [aws_security_group.lambda_in_vpc.id]
    subnet_ids = aws_db_subnet_group.rds.subnet_ids
  }
  # lambda in the VPC needs 'vpc_config' settings
  publish                     = true
  tags = {
      Name                    = "${local.lambda_name_loading}"
  }
}
#=======================================
#5 link lambda with SNS topics

resource "aws_lambda_function_event_invoke_config" "lambda-sns-loading" {
  function_name                = aws_lambda_function.data_mysql_loading.function_name
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
resource "aws_security_group" "lambda_in_vpc" {
  name        = "${local.prefix}-sg-lambda-in-cpv"
  description = "Place holder "
  vpc_id      = aws_vpc.web_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.prefix}-sg-lambda-in-cpv"
  }
}
# make sure rds SG allows lambda SG
resource "aws_security_group_rule" "lambda_to_rds" {
  type            = "ingress"
  from_port       = 3306
  to_port         = 3306
  protocol        = "tcp"
  #=====================================================
  source_security_group_id = aws_security_group.lambda_in_vpc.id
  #=====================================================
  security_group_id = aws_security_group.rds.id

}
# make sure rds SG allows lambda SG
resource "aws_security_group_rule" "rds_to_lambda" {
  type            = "ingress"
  from_port       = 3306
  to_port         = 3306
  protocol        = "tcp"
  #=====================================================
  source_security_group_id = aws_security_group.rds.id
  #=====================================================
  security_group_id = aws_security_group.lambda_in_vpc.id

}
data "aws_route_tables" "rds" {
  filter {
    name = "tag:Name"
    values = ["${local.prefix}-route-lambda"]
  }
}

#7 below lambda-s3 gateway can't be combined with ecs s3 gateway
# they may need to connect different s3 buckets and they reside in different subnets as well
# using one s3 gateway is too permissive
resource "aws_vpc_endpoint" "s3" {
  vpc_id = aws_vpc.web_vpc.id
  service_name = "com.amazonaws.${local.aws_region}.s3"
  route_table_ids =  data.aws_route_tables.rds.ids 
  # if lambda use the same subnets with RDS
  # the route tables are the same for both as well.
  vpc_endpoint_type = "Gateway" 
  # below policy is the same as policy for loading lambda 
  # just copy/paste from loading lambda
  # otherwise AWS will assign an 'allow-all' policy for endpoint
  policy = <<POLICY
  {
    "Statement": [
      {
        "Sid": "uploadbucket",
        "Effect": "Allow",
        "Principal": "*",
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
        "Sid": "backupbucket",
        "Effect": "Allow",
        "Principal": "*",
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
  }
  POLICY
  tags = {
    Name="${local.prefix}-vpv-endpoint-gateway-s3"
  }
}

# the above policy is attached to VPC, restricting VPC
# when it accesses S3;


# 7.2 below is to create vpc endpoint for secrets manager
#7.2.1 to create SG for endpoint first
# we needs ENDpoints to accept requests from resources in vpc on port 443

resource "aws_security_group" "vpc_endpoints_example" {
  name        = "${local.prefix}-sg-example"
  description = "VPC endponts must accept requests from ECS"
  vpc_id      = aws_vpc.web_vpc.id

  tags = {
    Name = "${local.prefix}-sg-example"
  }
}

resource "aws_security_group_rule" "lambda_to_vpc_endpoints" {
  type            = "ingress"
  from_port       = 443
  to_port         = 443
  protocol        = "tcp"
  source_security_group_id = aws_security_group.lambda_in_vpc.id

  security_group_id = aws_security_group.vpc_endpoints_ecr_secret_logs.id 
}

#7.2.2 below is to create vpc endpoint for secrets manager

resource "aws_vpc_endpoint" "secretsmanager_lambda" {
  vpc_id            = aws_vpc.web_vpc.id
  service_name      = "com.amazonaws.${local.aws_region}.secretsmanager"
  vpc_endpoint_type = "Interface"
  subnet_ids = aws_db_subnet_group.rds.subnet_ids
  security_group_ids = [aws_security_group.vpc_endpoints_example.id]
  private_dns_enabled = true

  policy = <<POLICY
  {
    "Statement": [
      {
        "Principal": "*",
        "Action": "secretsmanager:GetSecretValue",
        "Effect": "Allow",
        "Resource": [
          "${local.mysql-creds-db-maintanance-arn}"
        ]
      }
    ]
  }  
POLICY

  tags = {
    Name="${local.prefix}-vpc-endpoint-interface-secret"
  }
}
