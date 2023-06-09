###### Private ECS (Fargate) with VPC Endpoints #######
#============================================================
#0 to build docker image and push it to ECR (files shared in another repository)

#1 to create VPC with private subnets for ECS Fargate in each AZ (in another file)
  # for security reason, ECS should be in the private subnets
  # if ecs needs to pull from ECR, fetch secret from Secrets Manager,
  # ECR, Secrects Manager, etc, only provide public API 
  # ECS has to access them using internet gateway (internet traffic + public subnets), 
  # or NAT gateway (internet traffic + private subnets), or VPC Endpoints (Amazon network + private subnets)
  # the last 2 options will be more secure. What I most concern between them is cost.
  # One NAT gateway equals 4.5 times of VPC Endpoints. If more than 4 Endpoints (interface type) are deployed, I will choose NAT.
# private subnets--> 2 route tables--> 2 subnets--> 4 interface VPC Endpoints

#2 to create SG for ECS and VPC Endpoint
#3 to set up Interface VPC Endpoint for Secrect Manager, ECR DKR, ECR API, CloudWatch logs
  # to set up Gateway VPC Endpoint for S3
  # ECR requires 3 endpoints to work (one is gateway s3 endpoint, free),
  # the total interface endpoints for fargate are 4.
  # if in future more interface VPC endpoints are needed, delete them all and create NAT gateway
  # because NAT gateway is less expensive than 5 interface VPC endpoints

#4 to create ECS Cluster --> Service --> task definition --> Containers
    # for ECS cluster
    #4.0 to create log group for ECS 
    #4.1 to create ECS cluster
    #4.2 to create Task definition
      #4.2.1 to create role 1 --> Task Role
        # task role is to allow ECS to access other AWS services for tasks(s3, RDS, etc)
      #4.2.2 to create role 2 --> Execution Role
        # execution role is to allow ECS to access CloudWatch Logs, ECR, Secrets Manager. 
    #4.3 to create ECS task
    #4.4 to create ECS service

#5 to create ALB (in another file)
#6 to set up Auto Scaling 

#============================================================
#0 As another repo will share the dockerfile, python scripts, below are just general steps
  # Note: I prefer to create certain resources using AWS Console or CLI because these resources 
  # are not changing frequently. Like secrets managers, ACM (Certificates), Route53 hosted zones,
  # ECR, etc
  /*
  #0.1 to create private repo in ECR:
    # ("$" is not included in the command)
    $ aws ecr create-repository \
      --repository-name your_repo_name \        
      --image-scanning-configuration scanOnPush=true \
      --region your_aws_region
  # the response should be like:
  {
      "repository": {
          "repositoryArn": "arn:aws:ecr:region:accountid:repository/your_repo_name",
          "registryId": "accountid",
          "repositoryName": "your_repo_name",
          "repositoryUri": "accountid.dkr.ecr.region.amazonaws.com/your_repo_name",
          "createdAt": "2023-06-07T23:31:09-04:00",
          "imageTagMutability": "MUTABLE",
          "imageScanningConfiguration": {
              "scanOnPush": true
          },
          "encryptionConfiguration": {
              "encryptionType": "AES256"
          }
      }
  }
  (END)
  #0.2 to login your own repo
    $ aws ecr get-login-password --region your_region | docker login --username AWS --password-stdin accountid.dkr.ecr.region.amazonaws.com
  #0.3 to build docker image
    $ docker build -t image_name .
  #0.4 to tag image as latest
    $ docker tag image_name:latest accountid.dkr.ecr.region.amazonaws.com/your_repo_name    
  #0.5 to push/pull from ECR    
    $ docker push accountid.dkr.ecr.region.amazonaws.com/your_repo_name   
    $ docker pull accountid.dkr.ecr.region.amazonaws.com/your_repo_name:latest
*/
############################
###### Security Group ######
############################
#2 SG for ECS
resource "aws_security_group" "ecs_service" {
  name   = "${local.prefix}-sg-ecs-service"
  vpc_id = aws_vpc.example.id
  
  ingress {
    from_port   = local.ecs_container_port_1st
    to_port     = local.ecs_container_port_1st
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.example.cidr_block]
  # can restrict inbound rules by allowing ALB only
  }
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.example.cidr_block]
  }
  egress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.private-s3.prefix_list_id]
  }
  
  tags = {
    Name="${local.prefix}-sg-ecs-service"
  }
}

# SG for VPC Endpoint
# we needs ENDpoints to accept requests from ECS on port 443
resource "aws_security_group" "vpc_endpoints_ecr_secret_logs" {
  name        = "${local.prefix}-sg-vpc-endpoints-ecr-secretsmanager-cloudwatchlogs"
  description = "VPC endponts must accept requests from ECS"
  vpc_id      = aws_vpc.example.id

  tags = {
    Name = "${local.prefix}-sg-vpc-endpoints-ecr-secretsmanager-cloudwatchlogs"
  }
}
resource "aws_security_group_rule" "ecs_to_vpc_endpoints" {
  type            = "ingress"
  from_port       = 443
  to_port         = 443
  protocol        = "tcp"
  source_security_group_id = aws_security_group.ecs_service.id

  security_group_id = aws_security_group.vpc_endpoints_ecr_secret_logs.id 
}
############################
###### VPC Endpoints  ######
############################
#3 there are 3 endpoints for ECR: 
data "aws_route_tables" "ecs" {
  depends_on = [ aws_route_table.example ]
  filter {
    name = "tag:Name"
    values = ["${local.prefix}-example"]
  }
}
resource "aws_vpc_endpoint" "private-s3" {
  vpc_id = aws_vpc.example.id
  service_name = "com.amazonaws.${local.aws_region}.s3"
  vpc_endpoint_type = "Gateway" 
  route_table_ids = data.aws_route_tables.ecs.ids 
  /* >>>>>>>>>>>>>>>>> */
  policy = <<POLICY
  {
    "Statement": [
      {
        "Sid": "ecr",
        "Effect": "Allow",
        "Principal": "*",
        "Action": [
          "s3:GetObject"
        ],
        "Resource": [
          "arn:aws:s3:::prod-${local.aws_region}-starport-layer-bucket/*"
        ]
      }
    ]
  }
  POLICY

  tags = {
    Name="${local.prefix}-vpv-endpoint-gateway-s3"
  }
}
# the policies for dkr and api are the same
# dkr is to pull /push images
# api is for other actions
resource "aws_vpc_endpoint" "ecr-dkr" {
  vpc_id            = aws_vpc.example.id
  private_dns_enabled = true
  service_name      = "com.amazonaws.${local.aws_region}.ecr.dkr"
  vpc_endpoint_type = "Interface"
  subnet_ids = local.private_subnets
  security_group_ids = [aws_security_group.vpc_endpoints_ecr_secret_logs.id]
  
  /* >>>>>>> */
  policy = <<POLICY
  {
    "Statement": [
      {
        "Action": "ecr:*",
        "Effect": "Allow",
        "Principal": "*",
        "Resource": "arn:aws:ecr:${local.aws_region}:${local.AccountID}:repository/${local.repo_name}"
      },
      {
        "Effect": "Allow",
        "Action": [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability"  
        ],
        "Resource": "arn:aws:ecr:${local.aws_region}:${local.AccountID}:repository/${local.repo_name}",
        "Principal": "*"
      },
      {
        "Effect": "Allow",
        "Action": "ecr:GetAuthorizationToken",
        "Resource": "*",
        "Principal": "*"
      },
      {
        "Action": "ecr:DeleteRepository",
        "Effect": "Deny",
        "Principal": "*",
        "Resource": "arn:aws:ecr:${local.aws_region}:${local.AccountID}:repository/${local.repo_name}"
      }
    ]
  }
  POLICY
 
  tags = {
    Name="${local.prefix}-vpc-endpoint-interface-ecr-dkr"
  }
}
resource "aws_vpc_endpoint" "ecr-api" {
  vpc_id            = aws_vpc.example.id
  private_dns_enabled = true
  service_name      = "com.amazonaws.${local.aws_region}.ecr.api"
  vpc_endpoint_type = "Interface"
  subnet_ids = local.private_subnets
  security_group_ids = [aws_security_group.vpc_endpoints_ecr_secret_logs.id]
  
/* >>>>>>> */
policy = <<POLICY
 {
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability"  
        ],
        "Resource": "arn:aws:ecr:${local.aws_region}:${local.AccountID}:repository/${local.repo_name}",
        "Principal": "*"
      },
      {
        "Effect": "Allow",
        "Action": "ecr:GetAuthorizationToken",
        "Resource": "*",
        "Principal": "*"
      },
      {
        "Action": "ecr:DeleteRepository",
        "Effect": "Deny",
        "Principal": "*",
        "Resource": "arn:aws:ecr:${local.aws_region}:${local.AccountID}:repository/${local.repo_name}"
      }
    ]
  }
POLICY

  tags = {
    Name="${local.prefix}-vpc-endpoint-interface-ecr-api"
  }
}

resource "aws_vpc_endpoint" "cloudwatch" {
  vpc_id            = aws_vpc.example.id
  private_dns_enabled = true
  service_name      = "com.amazonaws.${local.aws_region}.logs"
  vpc_endpoint_type = "Interface"
  subnet_ids = local.private_subnets
  security_group_ids = [aws_security_group.vpc_endpoints_ecr_secret_logs.id]
  
/* >>>>>>>> */
  policy = <<POLICY
  {
    "Statement": [
      {
        "Principal": "*",
        "Action":  [
          "logs:CreateLogStream",
          "logs:CreateLogGroup",
          "logs:PutLogEvents"
        ],
        "Resource":  [
          "arn:aws:logs:${local.aws_region}:${local.AccountID}:log-group:${local.ecs_cluster_log_group}:*",
          "arn:aws:logs:${local.aws_region}:${local.AccountID}:log-group:${local.ecs_cluster_log_group}:log-stream:*"
        ],
        "Effect": "Allow"
      }
    ]
  }  
POLICY

  tags = {
    Name="${local.prefix}-vpc-endpoint-interface-cloudwatch"
  }
}
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id            = aws_vpc.example.id
  service_name      = "com.amazonaws.${local.aws_region}.secretsmanager"
  vpc_endpoint_type = "Interface"
  subnet_ids = local.private_subnets
  security_group_ids = [aws_security_group.vpc_endpoints_ecr_secret_logs.id]
  private_dns_enabled = true
/* >>>>>>> */
  policy = <<POLICY
  {
    "Statement": [
      {
        "Principal": "*",
        "Action": "secretsmanager:GetSecretValue",
        "Effect": "Allow",
        "Resource": [
          "${local.mysql-creds-arn}"
        ]
      }
    ]
  }  
POLICY

  tags = {
    Name="${local.prefix}-vpc-endpoint-interface-secret"
  }
}

#############################
###### Private Fargate ######
#############################
locals {
  ecs_cluster_log_group     = "ecs/fargate/${local.prefix}"
}
#4 ECS Cluster
resource "aws_cloudwatch_log_group" "ecs" {
  name = local.ecs_cluster_log_group
  tags = {
    Environment = "dev"
  }
}

resource "aws_ecs_cluster" "example" {
  depends_on = [ aws_cloudwatch_log_group.ecs ]
  name = "${local.prefix}-ecs-cluster"
  tags = {
    Name        = "${local.prefix}-ecs-cluster"
    Environment = var.environment
  }
}

# container definition for task
# >>>>>>>>>>>
#secrets=[
        #{"name":"secret_string", "valueFrom":"${local.mysql-creds-arn}"} 
      #]
locals {
  repo_name                 = local.prefix
  task_image_1              = "${local.AccountID}.dkr.ecr.${local.aws_region}.amazonaws.com/${local.prefix}:latest"
  ecs_container_port_1st    = 80
  ecs_container_port_2nd    = 443
  container_definition = [{
    cpu         = 1024
    image       = local.task_image_1
    memory      = 2048
    name        = "${local.prefix}-container-1"
    networkMode = "awsvpc"
    environment = [
      {"name":"rds_endpoint", "value": "${aws_db_instance.mysql.endpoint}"}, 
      {"name":"aws_region", "value": "${local.aws_region}"}
    ] 
    secrets=[
      {"name":"secret_string", "valueFrom":"${local.mysql-creds-arn}"} 
    ]
    portMappings = [
      {
        protocol      = "tcp"
        containerPort = local.ecs_container_port_1st
        hostPort      = local.ecs_container_port_1st
      }
    ]
    logConfiguration = {
      logdriver = "awslogs"
      options = {
        "awslogs-group"         = local.ecs_cluster_log_group
        "awslogs-region"        = local.aws_region
        "awslogs-stream-prefix" = "fargate"
      }
    }
  }]
}
output "task_image" {
  value=local.task_image_1
}
# ecs task role
resource "aws_iam_role" "ecs_task_role" {
  name = "${local.prefix}-ecsTaskRole"

  assume_role_policy = <<EOF
  {
   "Version":"2012-10-17",
   "Statement":[
      {
         "Effect":"Allow",
         "Principal":{
            "Service":[
               "ecs-tasks.amazonaws.com"
            ]
         },
         "Action":"sts:AssumeRole",
         "Condition":{
            "ArnLike":{
            "aws:SourceArn":"arn:aws:ecs:${local.aws_region}:${local.AccountID}:*"
            },
            "StringEquals":{
               "aws:SourceAccount":"${local.AccountID}"
            }
         }
      }
    ]
  }
EOF
}

# policy for task role --> CloudWatch
resource "aws_iam_policy" "ecs_logging_policy" {
  name   = "${local.prefix}-ecs-log-task"
  policy =  <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
        "Effect": "Allow",
        "Action": [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
        ],
        "Resource":[
          "arn:aws:logs:${local.aws_region}:${local.AccountID}:log-group:${local.ecs_cluster_log_group}:*",
          "arn:aws:logs:${local.aws_region}:${local.AccountID}:log-group:${local.ecs_cluster_log_group}:log-stream:*"
        ]
    }
  ]
}
EOF
}
/* >>>>>>>>>>>>
  resources = [
    "arn:aws:logs:${local.aws_region}:${local.AccountID}:log-group:${local.ecs_cluster_log_group}:*",
    "arn:aws:logs:${local.aws_region}:${local.AccountID}:log-group:${local.ecs_cluster_log_group}:log-stream:*"
  ]
*/
# policy for task role --> RDS
# if we attach AWS managed policy to the role
# can use terraform to find its arn
data "aws_iam_policy" "rds" {
  name = "AmazonRDSFullAccess"
}

resource "aws_iam_role_policy_attachment" "ecs-task-role-policy-attachment" {
  for_each =zipmap(
  [0,1],
  [
    tostring(data.aws_iam_policy.rds.arn),
    tostring(aws_iam_policy.ecs_logging_policy.arn)
  ])
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = each.value
}
# ecs task execution role
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${local.prefix}-ecs-TaskExecutionRole"

  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": "sts:AssumeRole",
     "Principal": {
       "Service": "ecs-tasks.amazonaws.com"
     },
     "Effect": "Allow",
     "Sid": ""
   }
 ]
}
EOF
}
# execution role is responsible for log, ecr and secrets
# policy for task execution role -> ECR 
resource "aws_iam_policy" "ECR" {
  name        = "${local.prefix}-policy-ecs-ecr"
  description = "Attached to ECS. it allows ECS to pull from ecr"
 
  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability"  
        ],
        "Resource": "arn:aws:ecr:${local.aws_region}:${local.AccountID}:repository/${local.repo_name}"
      },
      {
        "Effect": "Allow",
        "Action": [
            "ecr:GetAuthorizationToken"
        ],
        "Resource": "*"
      }
    ]
})
}
# policy for task execution role -> Secrets 

resource "aws_iam_policy" "SecretsManager" {
  name        = "${local.prefix}-policy-ecs-secretsmanager"
  path        = "/"
  description = "Attached to ECS. it allows ECS to get secrect of RDS"
 
  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
          "Effect": "Allow",
          "Action": [
            "secretsmanager:GetSecretValue",
            "ssm:GetParameters",
            "kms:Decrypt"
          ],
          "Resource": [
              "${local.mysql-creds-arn}"
          ]
      }
    ]
})
}

resource "aws_iam_role_policy_attachment" "ecs-task-execution-role-policy-attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy_attachment" "ecs-task-execution-role-policy-attachment-2" {

  for_each =zipmap(
  [0,1,2],
  [
    tostring(aws_iam_policy.ECR.arn),
    tostring(aws_iam_policy.SecretsManager.arn),
    tostring(aws_iam_policy.ecs_logging_policy.arn)
  ])
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = each.value
}
# task definition 
resource "aws_ecs_task_definition" "example" {
  depends_on = [ aws_db_instance.mysql ]
  family = "${local.prefix}-family-ecs-containers"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = local.container_definition.0.cpu
  memory                   = local.container_definition.0.memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  
  container_definitions = jsonencode(local.container_definition)
  
}

# ecs service
# ECS Service decides how many and how the tasks will run within which cluster
resource "aws_ecs_service" "example" {
  name                 = "${local.prefix}-ecs-service"
  #define cluser
  cluster              = aws_ecs_cluster.example.id
  #define task
  task_definition      = aws_ecs_task_definition.example.arn
  launch_type          = "FARGATE"
  #scheduling_strategy  = "REPLICA"
  desired_count        = 1
  #force_new_deployment = true
  #deployment_minimum_healthy_percent = 50
  #deployment_maximum_percent         = 200

  network_configuration {
    subnets          = local.private_subnets
    security_groups = [
      aws_security_group.ecs_service.id
    ]
  }
}

#6 below is to setup auto scaling

resource"aws_appautoscaling_target""ecs_target" {

  max_capacity       =2

  min_capacity       =1

  resource_id        ="service/${aws_ecs_cluster.example.name}/${aws_ecs_service.example.name}"

  scalable_dimension="ecs:service:DesiredCount"

  service_namespace  ="ecs"

}

resource"aws_appautoscaling_policy""ecs_policy_memory" {

  name               ="${local.prefix}-autoscaling-ecs-memory"

  policy_type        ="TargetTrackingScaling"

  resource_id        =aws_appautoscaling_target.ecs_target.resource_id

  scalable_dimension=aws_appautoscaling_target.ecs_target.scalable_dimension

  service_namespace  =aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {

    predefined_metric_specification {

    predefined_metric_type="ECSServiceAverageMemoryUtilization"

    }

    target_value=80

  }

}

resource"aws_appautoscaling_policy""ecs_policy_cpu" {

  name               ="${local.prefix}-autoscaling-ecs-cpu"

  policy_type        ="TargetTrackingScaling"

  resource_id        =aws_appautoscaling_target.ecs_target.resource_id

  scalable_dimension=aws_appautoscaling_target.ecs_target.scalable_dimension

  service_namespace  =aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {

    predefined_metric_specification {

    predefined_metric_type="ECSServiceAverageCPUUtilization"

    }

    target_value=80

  }

}