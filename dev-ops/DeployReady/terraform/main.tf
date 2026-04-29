terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# --- ECR ---

resource "aws_ecr_repository" "app" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Project = "kora-analytics" }
}

# delete old images automatically so storage stays within the free 500 MB limit
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# --- AMI ---

# look up the latest Ubuntu 22.04 AMI instead of hardcoding an ID that changes
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --- Security Group ---

resource "aws_security_group" "app" {
  name        = "kora-api-sg"
  description = "HTTP open to everyone, SSH locked to my IP"

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # port 22 is never open to 0.0.0.0/0
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.your_ip}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Project = "kora-analytics" }
}

# --- IAM role for the EC2 instance ---

# the server uses this role to pull images from ECR and write CloudWatch metrics
# so no AWS credentials need to be stored on the server
resource "aws_iam_role" "ec2_role" {
  name = "kora-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Project = "kora-analytics" }
}

resource "aws_iam_role_policy" "ec2_ecr_pull" {
  name = "ecr-pull"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchCheckLayerAvailability"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy" "ec2_cloudwatch" {
  name = "cloudwatch-metrics"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["cloudwatch:PutMetricData"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_instance_profile" "ec2_role" {
  name = "kora-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# --- IAM user for GitHub Actions ---

# separate user with only ECR push permissions — keeps pipeline credentials minimal
resource "aws_iam_user" "github_actions" {
  name = "github-actions-kora"
  tags = { Project = "kora-analytics" }
}

resource "aws_iam_user_policy" "github_actions_ecr" {
  name = "ecr-push"
  user = aws_iam_user.github_actions.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_access_key" "github_actions" {
  user = aws_iam_user.github_actions.name
}

# --- SSH key pair ---

resource "aws_key_pair" "deployer" {
  key_name   = "kora-deployer"
  public_key = file(var.ssh_public_key_path)
}

# --- EC2 instance ---

resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro" # free tier: 750 h/month for 12 months
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_role.name
  user_data              = file("${path.module}/user_data.sh")

  tags = {
    Name    = "kora-api"
    Project = "kora-analytics"
  }
}

# keeps the same public IP even if the instance is stopped and restarted
resource "aws_eip" "app" {
  instance = aws_instance.app.id
  domain   = "vpc"

  tags = { Project = "kora-analytics" }
}

# --- CloudWatch alarm ---

# optional SNS topic — only created when alert_email is set in tfvars
resource "aws_sns_topic" "alerts" {
  count = var.alert_email != "" ? 1 : 0
  name  = "kora-api-alerts"
  tags  = { Project = "kora-analytics" }
}

# AWS sends a confirmation email after apply — click the link to activate it
resource "aws_sns_topic_subscription" "email_alert" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# fires if /health returns non-200 for 2 minutes in a row
# treat_missing_data = "breaching" means a silent server also triggers the alarm
resource "aws_cloudwatch_metric_alarm" "health_check" {
  alarm_name          = "kora-api-health-check"
  alarm_description   = "GET /health is not returning 200"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthCheckStatus"
  namespace           = "KoraAnalytics"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  treat_missing_data  = "breaching"

  alarm_actions = var.alert_email != "" ? [aws_sns_topic.alerts[0].arn] : []
  ok_actions    = var.alert_email != "" ? [aws_sns_topic.alerts[0].arn] : []

  tags = { Project = "kora-analytics" }
}
