#!/bin/bash
set -euo pipefail

# Install Docker
dnf update -y
dnf install -y docker awscli
systemctl enable --now docker
usermod -aG docker ec2-user

# Install CloudWatch agent
dnf install -y amazon-cloudwatch-agent

# Configure Docker log driver for CloudWatch
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "awslogs",
  "log-opts": {
    "awslogs-region": "${aws_region}",
    "awslogs-group": "${log_group_name}",
    "awslogs-stream": "app-container"
  }
}
EOF
systemctl restart docker

# Pull and run the application
aws ecr get-login-password --region "${aws_region}" | \
  docker login --username AWS --password-stdin "${ecr_repository%%/*}"

docker pull "${ecr_repository}:${app_version}"

docker run -d \
  --name devops-app \
  --restart unless-stopped \
  -p 8080:8080 \
  -e ENV_NAME="${environment}" \
  -e APP_VERSION="${app_version}" \
  "${ecr_repository}:${app_version}"
