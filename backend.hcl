# backend.hcl
#below bucket and dynamo table is for storing terraform.tfstate safely
bucket         = "your bucket name"
region         = "your region"
dynamodb_table = "your table name"
encrypt        = true