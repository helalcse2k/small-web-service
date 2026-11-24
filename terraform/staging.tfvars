# staging.tfvars — override with production.tfvars for prod
environment        = "staging"
aws_region         = "us-east-1"
instance_type      = "t3.micro"
log_retention_days = 7
ecr_repository     = "123456789012.dkr.ecr.us-east-1.amazonaws.com/devops-task-service"
app_version        = "sha-abc1234"
