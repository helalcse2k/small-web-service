terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "devops-task-care-guide-tfstate"
    key            = "devops-task/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "devops-task-care-guide-tflock"
  }
}

provider "aws" {
  region = var.aws_region
}
