# staging.tfvars — Fill in YOUR real values before running terraform apply
# Run from: E:\Backup\Care-Guide\devops\solution\terraform\

environment        = "staging"
aws_region         = "us-east-1"
instance_type      = "t3.large"            # Needs 2 vCPU + 8 GB for Minikube
log_retention_days = 7
key_name           = "devops-task-key"     # SSH key pair name you will create in AWS

# Replace YOUR_ACCOUNT_ID with your real AWS account number
ecr_repository     = "YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/devops-task-service"

# This will be updated automatically by the CI/CD pipeline after first push
app_version        = "latest"
