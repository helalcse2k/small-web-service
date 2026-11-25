output "ec2_instance_id" {
  description = "EC2 instance ID — add this as GitHub secret EC2_INSTANCE_ID"
  value       = aws_instance.app.id
}

output "ec2_public_ip" {
  description = "EC2 public IP — add this as GitHub secret EC2_PUBLIC_IP"
  value       = aws_instance.app.public_ip
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.app.name
}

output "app_url" {
  description = "Application URL"
  value       = "http://${aws_instance.app.public_ip}:8080"
}

output "grafana_url" {
  description = "Grafana monitoring URL"
  value       = "http://${aws_instance.app.public_ip}:3000"
}

output "ssh_command" {
  description = "SSH command to connect to the EC2 instance"
  value       = "ssh -i ~/.ssh/devops-task-key.pem ec2-user@${aws_instance.app.public_ip}"
}
