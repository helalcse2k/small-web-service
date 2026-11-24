terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "devops-task-tfstate"      # pre-create this bucket
    key            = "devops-task/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "devops-task-tflock"       # pre-create this DynamoDB table
  }
}

provider "aws" {
  region = var.aws_region
}
