#=============================================================================================
#Below are terraform to build website based on AWS
#=============================================================================================

#The region will be obtained according to var.environment
#development, qa, staging, production
provider "aws" {
  profile = "default"
  region  = "${lookup(var.aws_region, var.environment)}"
  allowed_account_ids = local.AccountList
}
#common prefix for all resources' names and tags
locals {
  prefix="here is the string"
  #Below is to get timestamp for naming AWS resources
  current_timestamp  = timestamp()
  current_day        = formatdate("YYYY-MM-DD", local.current_timestamp)
  current_time       = formatdate("hh:mm:ss", local.current_timestamp)
  current_day_name   = formatdate("EEEE", local.current_timestamp) 
}

#===========================================================
# Below is to configure the backend for terraform state file
# The other settings (e.g., bucket, region) are stored in backend.hcl 
# Run 'terraform init -backend-config=backend.hcl'
terraform {
  backend "s3" {
    bucket         = "here is the bucket name"
    key = "here is the key for tfstate file"
    region         = "here is your region"
    dynamodb_table = "here is your dynamodb table name"
    encrypt        = true
  }
}
