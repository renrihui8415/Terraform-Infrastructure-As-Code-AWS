#### ECS -- Container Definitions
locals {
  ecs_container_port_1st= 80
  ecs_container_port_2nd= 443
  container_image_1st       = "username/image_from_dockerhub:latest"
  container_image_2nd       = "username/image_from_dockerhub:latest"
}

#============================================================
#1 to create VPC with public/private subnets in each AZ (in another file)
  # public subnets --> one route table --> one internet gateway
  # private subnets--> two route tables-->two nat gateway-->one internet gateway
#2 to create ECR where Docker images are kept (or docker hub)
#3 to create ECS Cluster --> Service --> task definition --> Containers
    # for ECS cluster
    #3.1 to create ECS cluster
    #3.2 to create Task definition
      #3.2.1 to create Task Definition
      #3.2.2 to create role 1 --> Task Role
      #3.2.3 to create role 2 --> Execution Role
    #3.4 to create ECS service
    #3.5 to create Security Group (in the file of VPC)
#4 to create ALB (in another file)
#5 to set up Auto Scaling 
#6 Cloud Watch
#============================================================
#2 below is to create ECR repository
# ECR is where we store Docker images. 
# The images can be pushed from locally to the ECR 
# or we use CICD platform to do it

resource "aws_ecr_repository" "example" {
  name = "${local.prefix}-ecr"
  image_tag_mutability = "MUTABLE"
}
# mutable tagging enables to put a latest tag on the most recent image

resource "aws_ecr_lifecycle_policy" "example" {
  repository = aws_ecr_repository.example.name

  policy = jsonencode({
   rules = [{
     rulePriority = 1
     description  = "keep last 10 images"
     action       = {
       type = "expire"
     }
     selection     = {
       tagStatus   = "any"
       countType   = "imageCountMoreThan"
       countNumber = 10
     }
   }]
  })
}
# the above is to keep only 10 images in the repo

#============================================================
#3 below is to create ECS Cluster:
# ECS Cluster contains
    # ECS service which contains
      # task definition which contains
        # containers
#============================================================
# 3.1 below is to create ECS cluster

resource "aws_ecs_cluster" "example" {
  name = "${local.prefix}-ecs-cluster"
  tags = {
    Name        = "${local.prefix}-ecs-cluster"
    Environment = var.environment
  }
}
# all the cluster needs is a name ...
#============================================================
#3.2 below is to create task definition
# AWS managed four roles for ECS:
# aaa) (EC2 Execution Role) EC2 Role for ECS
    # allows EC2 in an ECS cluster to access ECS
      # it contains policy of "AmazonEC2ContainerServiceforEC2Role"
      # it includes permissions for CloudWatch Logs, EC2, ECR, ECS
# bbb) ECS Role
    # allows ECS to create and manage AWS resources on your behalf
      # it contains policy of "AmazonEC2ContainerServiceRole"
      # it includes permissions of EC2, ELB, ELB v2
# ccc) ECS Autoscale Role
    # allows Auto Scaling to access and update ECS
      # it contains policy of "AmazonEC2ContainerServiceAutoscaleRole"
      # it includes permissions of CloudWatch Logs, ECS
# ddd) (Fargate Execution Role) ECS Task
    # allows ECS tasks to call AWS services on your behalf
      # it contains policy of "AmazonECSTaskExecutionRolePolicy"
### eee) Apart from the above, based on task defintion, a task role should be specifically created
    # for example, to allow task access S3.
#============================================================
#3.2.1 to create a task definition, a task role is needed
# This will allow the task access to other AWS resources 
# based on the task definition
resource "aws_ecs_task_definition" "example" {
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  #256=0.25vCPU
  #https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html
  memory                   = 2048
  # in mib
  # do refer to AWS Docs for cpu and memory setup

  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  family = "${local.prefix}-family-ecs-containers"

  container_definitions = jsonencode([
    {
      name        = "${local.prefix}-container-1"
      image       = "${local.container_image_1st}"
      essential   = true
      # In my case, 
      # there is a default port of 3000 in docker file
      # here I need to add port 80 so that 3000 won't be used
      environment = [
        {"name":"PORT", "value": "80"}
      ]
      portMappings = [{
        protocol      = "tcp"
        # for fargate, containerPort must be identical with hostPort
        containerPort = local.ecs_container_port_1st
        hostPort      = local.ecs_container_port_1st
      }]
    }
  ])
    # below is the template to add a sencond container definition
     /* 
    {
      name        = "${local.prefix}-container-2"
      image       = "${local.container_image_2nd}"
      essential   = true
      environment : [
        {"name":"PORT", "value": "443"}
      ]
      portMappings = [{
        protocol      = "tcp"
        # port :443
        containerPort = local.ecs_container_port_2nd
        hostPort      = local.ecs_container_port_2nd
      }]
    }
  ])s
  */
}

#============================================================
#3.2.2 below is to create ECS task role
resource "aws_iam_role" "ecs_task_role" {
  name = "${local.prefix}-ecsTaskRole"

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

# if the task requires access to S3
# then create a policy accordingly
resource "aws_iam_policy" "s3" {
  name        = "${local.prefix}-policy-ecs-s3"
  description = "Policy that allows access to s3"

 policy = <<EOF
{
   "Version": "2012-10-17",
   "Statement": [
       {
           "Effect": "Allow",
           "Action": [
               "s3:getObject",
               (actions needed for the task are list here)
           ],
           "Resource": "here is the arn of s3 bucket"
       }
   ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecs-task-role-policy-attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.s3.arn
}
#============================================================
#3.3.3 to create Execution-Role for farget service:
# a Execution role is needed for both types of ECS:
# fargate launch type and EC2 launch type
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
# aws has managed policy for this role, there s no need to create policy on our own
# unless the managed policy is not suitable for your project
# please remember to always grant the least priviledge to the task
resource "aws_iam_role_policy_attachment" "ecs-task-execution-role-policy-attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

#============================================================
#3.4 below is to create ECS Service
# ECS Service decides how many and how the tasks will run within which cluster

resource "aws_ecs_service" "example" {
  name                 = "${local.prefix}-ecs-service"
  #define cluser
  cluster              = aws_ecs_cluster.example.id
  #define task
  task_definition      = aws_ecs_task_definition.example.arn
  launch_type          = "FARGATE"
  scheduling_strategy  = "REPLICA"
  desired_count        = 5
  force_new_deployment = true
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = local.private_subnets.*
    assign_public_ip = false
    security_groups = [
      aws_security_group.ecs_service.id
    ]
  }
  
  load_balancer {
    target_group_arn = aws_lb_target_group.alb_ecs.arn
    container_name   = "${local.prefix}-container-1"
    container_port   = local.ecs_container_port_1st
    #to change to port 443 later in production environment
  }
  
  lifecycle {
    ignore_changes = [ task_definition,desired_count ]
  }
  depends_on = [aws_lb_listener.https]
}
#============================================================
#5 below is to setup auto scaling
resource"aws_appautoscaling_target""ecs_target" {
  max_capacity       =2
  min_capacity       =1
  resource_id        ="service/${aws_ecs_cluster.example.name}/${aws_ecs_service.example.name}"
  scalable_dimension ="ecs:service:DesiredCount"
  service_namespace  ="ecs"
}

resource"aws_appautoscaling_policy""ecs_policy_memory" {
  name               ="${local.prefix}-autoscaling-ecs-memory"
  policy_type        ="TargetTrackingScaling"
  resource_id        =aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension =aws_appautoscaling_target.ecs_target.scalable_dimension
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
  scalable_dimension =aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  =aws_appautoscaling_target.ecs_target.service_namespace
  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
    predefined_metric_type="ECSServiceAverageCPUUtilization"
    }
    target_value=80
  }
}
#============================================================
#6 below is to create log group on CloudWatch
resource "aws_cloudwatch_log_group" "ecs_cluster" {
  name = "${local.prefix}-logs-ecs-cluster"
  tags = {
    Name = "${local.prefix}-logs-ecs-cluster"
    Environment = var.environment
  }
}
#============================================================