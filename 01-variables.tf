#variable only offers hard values,
#local can use functions and variant of values
#============================================================
# AWS Region
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
#below is to decide which environment to use
#using the environment value we can get the desired aws region
variable "environment" {
    type = string
    description = "Options: development, qa, staging, production"
    default = "development"
}

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
#below is to convert the above MAP to a LIST!
#this list can be provided to provider.aws.allowed_ids:
locals {
  AccountList=[
    for r in local.AccountIds:"${r.id}"
  ]
}
#below is get a specific account id
locals {
  AccountID=local.AccountList[0]
}

#============================================================
#System name can be optional
#it just helps to tell the resources built by terraform from other resources
variable "system_name" {
  default="here is the string"
}
#============================================================
#below is to get available zones
data "aws_availability_zones" "available" {
  state = "available"
}
#below gives a tumple with multiple elements about available zones
locals {
  availability_zones = data.aws_availability_zones.available.names
  # to get the number of AZs in one AWS region
  no_az_all="${length(local.availability_zones)}"
}
#output all AZs 
output "all_azs" { 
  value = data.aws_availability_zones.available.names 
  description = "All AZs" 
} 
# different region has different number of AZs, like in us-east-1 has 6 AZs
#============================================================
#Note: 
# instance types are not supported in all AZs in aws
# need to check if desired instance type(s) are supported 
# otherwise, error throws when creating ASG (autoscaling group)

# As ECS was added into this project recently,
# VPC, subnets and AZ need modifying.
# Not all regions support ECS with a fargate launch type. 
# unfortunately, Terraform does not have a managed resource to get all those AZ that support fargate
# There is no way but manually add those AZs according to AWS docs.
#https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate-Regions.html
locals {
  az_for_fargate=["first supporting AZ","second supporting AZ"]
}

# below is for EC2 ASG, ECS with EC2 launch type
# just for reference
/*
locals {
  instance_type="t2.micro"
  instance_type_alternative="t3.micro"
}

# Select the AZs that support the primary instance type
data "aws_ec2_instance_type_offerings" "primary-instance" { 
  filter { 
    name   = "instance-type" 
    values = [local.instance_type]
  } 
  location_type = "availability-zone" 
} 
locals {
  az_for_pri=data.aws_ec2_instance_type_offerings.primary-instance.locations
  no_az_for_pri="${length(local.az_for_pri)}"
}

#output the valid AZs for the primary type
output "azs_that_support_primary_instance" { 
  value =  local.az_for_pri
  description = "AZs that support the t2.micro" 
} 
# the above is to show which AZs support t2.micro

# next is to find all AZs that support t3.micro
data "aws_ec2_instance_type_offerings" "secondary-instance" { 
  filter { 
    name   = "instance-type" 
    values = [local.instance_type_alternative]
  } 
  location_type = "availability-zone" 
} 
locals {
  az_for_sec=data.aws_ec2_instance_type_offerings.secondary-instance.locations
}
#output the valid AZs for t3
#output "azs_that_support_secondary_instance" { 
  #value=local.az_for_sec
  #description = "AZs that support the t3.micro" 
#} 
#next is to pick out the AZ which supports t3 but not t2
locals { 
  az_for_diff=[
    for az in local.availability_zones:
      !contains(local.az_for_pri,az) ? az : ""
  ]
}
# the AZs supporting both t2 and t3 will be shown as null values
# in the result
locals {
  az_that_support_t3_only=[  
    for az in local.az_for_diff:
      "${az}"
      if az != ""
  ]
  # to delete all null values in the list
  no_az_for_sec="${length(local.az_that_support_t3_only)}"
}
output "az_that_support_t3_only" {
  value=local.az_that_support_t3_only
}
*/

#============================================================
# next is to build subnets in supported AZs respectively 
# the cidr should be in the format of 
# x.x.x.x/24 or x.x.x.x/16
#============================================================
#below is to get the first half of cidr for vpc and subnet
#Note: 
# the cidr_block should be planned carefully ahead
# for public/private/DB..etc
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
  
    cidr_c_public_subnets   = 10
    #public subnets will be xxx.xx.10.0/24,
    #                       xxx.xx.11.0/24...
    #for 2nd instance type:
    #public subnets will be xxx.xx.100.0/24,
    cidr_c_public_subnets_2 =20

    cidr_c_private_subnets  = 30
    #private subnet will start from 30
    # which is xxx.xx.30.0/24
    cidr_c_private_subnets_2  = 40
    #the second subnets is for the secondary instance type

    cidr_c_database_subnets = 50
    # the private subnets for database will start from 50


    max_private_subnets     = 3
    max_database_subnets    = 3
    max_public_subnets      = 3
}

# subnets for t2.micro
# below can be omitted as it just tells you what the subnets are 
# if they are created 
# the creating process is done by terraform resource aws_subnet
locals {
  private_subnets_pri = [
      for az in local.az_for_pri : 
          "${lookup(var.cidr_ab, var.environment)}.${local.cidr_c_private_subnets + index(local.az_for_pri , az)}.0/24"
          if index(local.az_for_pri , az) < local.max_private_subnets && az != ""
      ]

  public_subnets_pri = [
      for az in local.az_for_pri  : 
          "${lookup(var.cidr_ab, var.environment)}.${local.cidr_c_public_subnets + index(local.az_for_pri , az)}.0/24"
          if index(local.az_for_pri , az) < local.max_public_subnets && az != ""
      ]
}
output "public_subnets_for_t2" {
  value=local.public_subnets_pri
}
#====================================================
# subnets for t3.micro only
# below can be omitted as it just tells you what the subnets are 
# if they are created 
# the creating process is done by terraform resource "aws_subnet"
locals {

  private_subnets_sec = [
    for az in local.az_that_support_t3_only : 
        "${lookup(var.cidr_ab, var.environment)}.${local.cidr_c_private_subnets_2 + index(local.az_that_support_t3_only , az)}.0/24"
        if index(local.az_that_support_t3_only , az) < local.no_az_for_sec && az != ""
    ]
  public_subnets_sec = [
    for az in local.az_that_support_t3_only  : 
        "${lookup(var.cidr_ab, var.environment)}.${local.cidr_c_public_subnets_2 + index(local.az_that_support_t3_only , az)}.0/24"
        if index(local.az_that_support_t3_only , az) < local.no_az_for_sec && az != ""
    ]
}
output "public_subnets_for_t3" {
  value=local.public_subnets_sec
}
#============================================================
# below is your own IP for the testing environment:
variable "yourownIP" {
  default = "xx.xx.xx.xx/32"
  sensitive = true
}
#============================================================
# for cloudfront, we need one provider other than default
# as AWS requires us-east-1 to be the only region for resources of cloudfront
provider "aws" {
  alias  = "here is the name for another provider"
  region = "us-east-1"
}
#============================================================
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
#below is for the bucket for domain_name:
locals  {
  bucket_name_for_web    = "www.${local.domain_name}"
}
#============================================================
#below is for SQS
variable "sqs_name" {
  type=string
  default = "s3-sqs-lambda" 
}
variable "dlq_name" {
  type = string
  default = "sqs-lambda-dlq"
}
#============================================================
#below is for sns:
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
#output "sns_topics_name" {
  #value=local.sns_topics_name
#}
#get the topic ARNs for sns topics
locals {
  topic_arn_on_success=join(":",["arn:aws:sns","${local.aws_region}","${local.AccountID}","${local.sns_topic_name}"])
  topic_arn_on_failure=join(":",["arn:aws:sns","${local.aws_region}","${local.AccountID}","${local.sns_topic_name2}"])
  topic_arn_on_dlq=join(":",["arn:aws:sns","${local.aws_region}","${local.AccountID}","${local.sns_topic_sqs_alert}"])
}
locals {
  sns_topics_arn=[local.topic_arn_on_success,local.topic_arn_on_failure,local.topic_arn_on_dlq]
}
#output "sns_topics_arn" {
  #value=local.sns_topics_arn
#}
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
   description = "SNS subscription protocal"
 }
#============================================================
#below is the layer for lambda function:
variable "AWSSDKPandas" {
  description = "part of the name of aws managed layer version"
  default = ":336392948345:layer:AWSSDKPandas-Python39:8"
}
locals {
  AWSSDKPandas=join("",["arn:aws:lambda:","${local.aws_region}","${var.AWSSDKPandas}"])
}
#============================================================
#### Cloudfront -- Custom Header ####
locals {
  cf_custom_header ="some characters"
  cf_custom_header_value="some characters"
}
# these values can be stored in secret manager
#### ALB -- Target Group -- Health Check ####
locals {
  tg_health_check_path="/"
}
#============================================================
#### RDS Secret ####
# first to manually create a key pair in secrets manager
# i didn't use secret format for RDS 
# i used general format (key pair) in the Secrets Manager
# find the secret using terraform
data "aws_secretsmanager_secret_version" "mysql-creds" {
  # Fill in the name you gave to your secret
  secret_id = "here is the name you give to your key pair"
}
locals {
  mysql-creds = jsondecode(
    data.aws_secretsmanager_secret_version.mysql-creds.secret_string
  )
}
# from the secret_string, the terraform can create rds using your username/password pair
# later you can use this username and password to log in your rds
locals {
  mysql-creds-arn =data.aws_secretsmanager_secret_version.mysql-creds.arn
}
# you can also get the arn for the secret

# in this project, i use another user for detailed task.
# the master user won't be used for daily work.