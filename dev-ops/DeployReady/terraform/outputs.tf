output "ec2_public_ip" {
  description = "Server public IP — add as EC2_HOST in GitHub secrets and use for the submission health check"
  value       = aws_eip.app.public_ip
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.app.repository_url
}

output "github_actions_access_key_id" {
  description = "Add as AWS_ACCESS_KEY_ID in GitHub secrets"
  value       = aws_iam_access_key.github_actions.id
}

output "github_actions_secret_access_key" {
  description = "Add as AWS_SECRET_ACCESS_KEY in GitHub secrets — run: terraform output -raw github_actions_secret_access_key"
  value       = aws_iam_access_key.github_actions.secret
  sensitive   = true
}

output "ssh_connect_command" {
  description = "SSH command to connect to the server"
  value       = "ssh -i ~/.ssh/id_rsa ubuntu@${aws_eip.app.public_ip}"
}

output "health_check_url" {
  description = "URL to test after deployment"
  value       = "http://${aws_eip.app.public_ip}/health"
}

output "cloudwatch_alarm_name" {
  description = "CloudWatch alarm name — view in: AWS Console → CloudWatch → Alarms"
  value       = aws_cloudwatch_metric_alarm.health_check.alarm_name
}
