variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (staging | production)"
  type        = string
  default     = "staging"

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be 'staging' or 'production'."
  }
}

variable "app_version" {
  description = "Docker image tag to run"
  type        = string
  default     = "latest"
}

variable "ecr_repository" {
  description = "Full ECR repository URI (without tag)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.large"   # t3.large needed for Minikube (2 vCPU, 8 GB RAM)
}

variable "key_name" {
  description = "EC2 SSH key pair name (must exist in AWS)"
  type        = string
  default     = "devops-task-key"
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "allowed_cidr" {
  description = "CIDR blocks allowed to reach port 8080"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
