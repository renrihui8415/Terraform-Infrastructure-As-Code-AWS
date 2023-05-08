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
    cidr_c_private_subnets  = 20
    #private subnet will start from 20
    # which is xxx.xx.20.0/24
    cidr_c_private_subnets_2  = 200
    #the second subnets is for the secondary instance type

    cidr_c_public_subnets   = 10
    #public subnets will be xxx.xx.10.0/24,
    #                       xxx.xx.11.0/24...
    #for 2nd instance type:
    #public subnets will be xxx.xx.100.0/24,
    cidr_c_public_subnets_2 =100

    max_private_subnets     = 3
    #multiple subnets in multiple AZs to achieve high availability
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
# below is your own IP for the dev environment:
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
#below is for the bucket for domain_name:
locals  {
  bucket_name_for_web    = "here is the bucket name for the website"
}

