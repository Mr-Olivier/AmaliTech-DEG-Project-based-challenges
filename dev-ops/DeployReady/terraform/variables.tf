variable "aws_region" {
  description = "AWS region to deploy to"
  type        = string
  default     = "us-east-1"
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository that stores Docker images"
  type        = string
  default     = "kora-analytics-api"
}

variable "your_ip" {
  description = "Your public IP address — SSH access is locked to this IP only. Find it at https://whatismyip.com"
  type        = string
}

variable "alert_email" {
  description = "Email to receive CloudWatch alarm notifications. Leave empty to skip."
  type        = string
  default     = ""
}

variable "ssh_public_key_path" {
  description = "Path to your SSH public key file (.pub). The private key is what you paste into the EC2_SSH_KEY GitHub secret."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}
