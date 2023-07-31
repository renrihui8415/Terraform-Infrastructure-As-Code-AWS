# Module of variable only offers hard values,
# Module of locals can use functions and variant of values
#============================================================
# for cloudfront, we need one provider other than default
# as AWS requires us-east-1 as the only region for certificate for cloudfront
provider "aws" {
  alias  = "acm_provider"
  region = "us-east-1"
}
#============================================================
#### AWS Region ####
# below is an example of changing regions
# in different phases of the project.

variable "aws_region" {
  description = "AWS Region"
  type        = map
  default = {
    "development" = "aws-region-1"
    "qa"          = "aws-region-2"
    "staging"     = "aws-region-3"
    "production"  = "aws-region-4"
  }
}
locals {
  aws_region="${lookup(var.aws_region, var.environment)}"
}
#============================================================
#### AWS Environment ####
#below is to decide which environment to use
#using the environment value we can get the desired aws region
variable "environment" {
    type = string
    description = "Options: development, qa, staging, production"
    default = "development"
}
#### AWS Account No. ####
#below enviroment is for aws account
locals {
  AccountIds={
    "account0"={
      "email"="your email address"
      "id"="your AWS account No."
    },
    "account1"={
      "email"="your 2nd email address"
      "id"="your 2nd AWS account No."
    }
  }
  
}
#below is to convert the above MAP to a LIST
#this list can be provided to provider.aws.allowed_ids:
locals {
  AccountList=[
    for r in local.AccountIds:"${r.id}"
  ]
}
#below is get a specific account id
locals {
  # to get the AccountID your data center is built in
  AccountID=local.AccountList[0]
}
#============================================================
#System name can be optional
#it just helps to tell the resources built by which project
variable "system_name" {
  default="here is the string"
}
#============================================================
#### Website Domain, Subdomains ####
# below are domains for your resources (Cloudfront, ALB, S3)
locals {
  domain_name="example.com"
}
locals {
  domain_name_alb="alb.example.com"
}
locals {
  domain_name_cf="cf.example.com"
  domain_name_cf_s3="cfs3.example.com"
}
locals {
  domain_name_subdomain_s3="www.example.com"
}
#============================================================
#### S3 Buckets ####
#below is the bucket store the uploaded data 
locals  {
  bucket_name_for_db    = "${local.prefix}-upload"
}
#below is the bucket for domain_name:
locals  {
  bucket_name_for_web    = "www.${local.domain_name}"
}
#============================================================
#### S3 Buckets ####
#below is the bucket to backup or store report data
#it is pre-built and won't be destroyed with Terraform Commands
variable "bucket_for_backup_sourcedata" {
  description="the bucket to backup uploaded files and to provide source data for BI tool"
  default="here is your bucket name"
}
variable "bucket_arn_for_backup_sourcedata" {
  description="the bucket to backup uploaded files and to provide source data for BI tool"
  default = "arn:aws:s3:::your_bucket_name"
}
#============================================================
#### SQS ####
#below is SQS for Data ETL 
variable "sqs_name" {
  type=string
  default = "s3-sqs-lambda" 
}
variable "dlq_name" {
  type = string
  default = "sqs-lambda-dlq"
}
#below is SQS for Cloudfront Cache Invalidation 
variable "sqs_name_data_analysis" {
  type=string
  default = "data-analysis" 
}
variable "dlq_name_data_analysis" {
  type = string
  default = "data-analysis-dlq"
}
#============================================================
#### SNS ####
#below is variables for SNS
#in this project, Lambda and CloudWatch publish messages through SNS topics
variable "sns_topic_name" {
  type = string
  description = "sns topic name"
  default = "here is the word you define as success or any topic for yes"
}
locals {
  sns_topic_name="${local.prefix}-topic-${var.sns_topic_name}"
}
variable "sns_topic_name2" {
  type = string
  description = "sns topic name2"
  default = "here is the word you define as failure or any topic for no"
}
locals {
  sns_topic_name2="${local.prefix}-topic-${var.sns_topic_name2}"
}
variable "sns_topic_sqs_alert" {
  type = string
  description = "sns topic sqs_alert"
  default = "dead-letter-queue"
}
locals {
  sns_topic_sqs_alert="${local.prefix}-topic-${var.sns_topic_sqs_alert}"
}
locals {
  sns_topics_name=[local.sns_topic_name,local.sns_topic_name2,local.sns_topic_sqs_alert]
}

locals {
  # to create ARN of SNS topics on your own
  topic_arn_on_success=join(":",["arn:aws:sns","${local.aws_region}","${local.AccountID}","${local.sns_topic_name}"])
  topic_arn_on_failure=join(":",["arn:aws:sns","${local.aws_region}","${local.AccountID}","${local.sns_topic_name2}"])
  topic_arn_on_dlq=join(":",["arn:aws:sns","${local.aws_region}","${local.AccountID}","${local.sns_topic_sqs_alert}"])
}
locals {
  sns_topics_arn=[local.topic_arn_on_success,local.topic_arn_on_failure,local.topic_arn_on_dlq]
}

variable "sns_subscription_email_address_list" {
  type = string
  description = "List of email addresses as string(space separated)"
  default = "1234@example.com"
}
variable "sns_subscription_email_address_list2" {
  type = list(string)
  description = "List of email addresses as string(space separated)"
  default = ["aaa@gmail.com", "bbb@gmail.com","ccc@outlook.com"]
}
variable "sns_subscription_protocol" {
   type = string
   default = "email"
   description = "SNS subscription protocol"
 }
#============================================================
#### Lambda ####
#below is the layer for lambda function:
#search here for the correct ARN 
#https://aws-sdk-pandas.readthedocs.io/en/stable/layers.html
variable "AWSSDKPandas" {
  description = "part of the name of aws managed layer version"
  default = ":336392948345:layer:AWSSDKPandas-Python39:8"
}
locals {
  AWSSDKPandas=join("",["arn:aws:lambda:","${local.aws_region}","${var.AWSSDKPandas}"])
}
#============================================================
#### Availability Zone ####
#below is to get available zones for your region defined previously
data "aws_availability_zones" "available" {
  state = "available"
}
#below gives a tumple with multiple elements about available zones
locals {
  availability_zones = data.aws_availability_zones.available.names
  # to get the number of AZs in one AWS region
  no_az_all="${length(local.availability_zones)}"
}
#output all AZs (optional)
output "all_azs" { 
  value = data.aws_availability_zones.available.names 
  description = "All AZs" 
} 
# different region has different number of AZs, like us-east-1 has 6 AZs
#Note: 
# EC2 Instance Type (or ECS in Fargate Type) is not supported in all AZs in AWS
# Error throws when creating ASG (autoscaling group) if unsupported type is found by AWS 

# We need to check if desired resources are supported in our target region.
# Terraform provides service to check for EC2. But it does not have a managed resource to get all those AZs that support fargate.
# If you apply EC2, you can build Terraform codes to automatically check for you.
# While for ECS, unfortunately, there is no way but to manually add those AZs in below modules according to AWS docs.
# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate-Regions.html
# Hopefully, Terraform will add a new resource and help us check for Fargate soon ^.^
locals {
  az_for_fargate=["first supporting AZ","second supporting AZ"]
}

# for EC2:
# define the desired instances type:
locals {
  instance_type="t2.micro"
  instance_type_alternative="t3.micro"
}
# to select the AZs that support my primary instance type 
data "aws_ec2_instance_type_offerings" "supports-my-instance" { 
  filter { 
    name   = "instance-type" 
    values = [local.instance_type]
  } 
  location_type = "availability-zone" 
} 
locals {
  az_for_pri=data.aws_ec2_instance_type_offerings.supports-my-instance.locations
  # get all AZs supporting t2.micro
  no_az_for_pri="${length(local.az_for_pri)}"
  # get how many AZs not supporting t2.micro in current AWS region
}
# to find all AZs that support my secondary instance type
data "aws_ec2_instance_type_offerings" "supports-my-instance-2" { 
  filter { 
    name   = "instance-type" 
    values = [local.instance_type_alternative]
  } 
  location_type = "availability-zone" 
} 
locals {
  az_for_sec=data.aws_ec2_instance_type_offerings.supports-my-instance-2.locations
  #get all AZs supporting t3.micro
}
# after we get AZs for primary and secondary types,
# 2 sets of AZs can overlap
# to pick out the AZs which supports secondary instance only
locals { 
  az_for_diff=[
    for az in local.availability_zones:
      !contains(local.az_for_pri,az) ? az : ""
  ]
}
locals {
  az_that_support_t3_only=[  
    for az in local.az_for_diff:
      "${az}"
      if az != ""
  ]
  # to delete all null values in the list
  # because the list of 'az_that_support_t3_only' we got contains null values
  no_az_for_sec="${length(local.az_that_support_t3_only)}"
  # to get how many AZs support t3.micro only
}
# since we get the right AZs for our primary and secondary instance types respectively
# next is to build subnets for the instances 
#============================================================
#### Subnets ####
# next is to build subnets in supported AZs respectively 
# the cidr should be in the format of 
# x.x.x.x/24 or x.x.x.x/16
#============================================================
#below is to get the first half of cidr for vpc and subnet
# Note: 
# the cidr_block should be planned carefully ahead
# you can let terraform to generate randomly for you
# at least you control within which IP Ranges Terraform can generate subnets randomly
variable "cidr_first_half" {
    type = map
    default = {
        development     = "xxx.xx"
        qa              = "xxx.xx"
        staging         = "xxx.xx"
        production      = "xxx.xx"
    }
}
#below is to get the third part of cidr 
#(like 172.31.1.x/24)
#and determines the max number of subnets that should be created 

locals {
    #------------------------------------------
    cidr_c_public_subnets     = 10
    #public subnets will be xxx.xx.10.0/24,
    #                       xxx.xx.11.0/24...
    #for 2nd instance type:
    #public subnets will be xxx.xx.100.0/24,
    #------------------------------------------
    cidr_c_public_subnets_2   = 20
    #------------------------------------------   
    cidr_c_private_subnets    = 30
    #private subnet will start from 30
    # which is xxx.xx.30.0/24
    #------------------------------------------
    cidr_c_private_subnets_2  = 40
    #the second subnets is for the secondary instance type
    #------------------------------------------
    cidr_c_database_subnets   = 50
    # the private subnets for database will start from 50
    #------------------------------------------
    max_private_subnets       = 3
    max_database_subnets      = 3
    max_public_subnets        = 3
}

#====================================================
# below is your own IP for the testing environment:
variable "yourownIP" {
  default = "xx.xx.xx.xx/32"
  sensitive = true
}
#============================================================
#### Cloudfront -- Geo Restriction ####
locals {
  geo_restriction=["US","CA","name_code of the desired countries"]
}
#### Cloudfront -- Custom Header ####
locals {
  cf_custom_header ="some characters"
  cf_custom_header_value="some characters"
}
# These values can be stored in Secrets Manager
#============================================================
#### ALB -- Target Group -- Health Check ####
locals {
  tg_health_check_path="/"
}
#============================================================
#### RDS Secret ####
# first to manually create a key pair in Secrets Manager in AWS Console
# i didn't use secret format for RDS 
# i used general format (key pair) in the Secrets Manager
data "aws_secretsmanager_secret_version" "mysql-creds" {
  # Fill in the name you gave to your secret
  secret_id = "here is the name you give to your key pair in AWS Console"
}
locals {
  mysql-creds = jsondecode(
    data.aws_secretsmanager_secret_version.mysql-creds.secret_string
  )
}
# from the secret_string, the terraform can create rds using your username/password pair
locals {
  mysql-creds-arn =data.aws_secretsmanager_secret_version.mysql-creds.arn
}
# later ECS can use this username and password to log in your rds
# the user we used to create RDS is a master user, and it's too powerful
# I don't use it to complete the daily task like Data ETL
# After ECS login the RDS, it will create a Admin User.
# The Admin user will be used by ECS and Lambda later for detailed work.

#### RDS Secret- for db maintanance ####
# first to manually create a key pair in secrets manager
# find the secret using terraform
data "aws_secretsmanager_secret_version" "mysql-creds-db-maintanance" {
  # Fill in the name you gave to your secret
  secret_id = "here is the name you give to your key pair in AWS Console"
}
locals {
  mysql-creds-db-maintanance = jsondecode(
    data.aws_secretsmanager_secret_version.mysql-creds-db-maintanance.secret_string
  )
}
locals {
  mysql-creds-db-maintanance-arn =data.aws_secretsmanager_secret_version.mysql-creds-db-maintanance.arn
}
#============================================================
#### Lambda+Docker Image ####
# below is the repository name in ECR
locals {
  lambda_repo_name="your repo name"
}