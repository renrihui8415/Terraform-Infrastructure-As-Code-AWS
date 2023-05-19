# This is for the project to create my own website. I share this so as to keep track of the website building.

# Architecture overview

Please refer to _Architecture_Diagram_Website_with_AWS.png

# aws-website building

The website is based on AWS resources (VPC, ALB, Route53, ASG, S3, ESC, Cloudfront, ACM, WAF, SQS, SNS, CloudWatch, IAM...)

## Requirements

* AWS CLI (with at least one profile)
* Terraform (website building automation)
* Python (Lambda Function automation)

## Deploying

terraform init
terraform validate
terraform plan
terraform apply
terraform destroy
