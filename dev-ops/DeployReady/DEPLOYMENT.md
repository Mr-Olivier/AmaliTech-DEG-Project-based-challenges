# Deployment Guide

## Cloud Provider: AWS

I chose AWS because the Free Tier covers everything this project needs — EC2 t3.micro runs 24/7 for 12 months at no cost, and ECR gives 500 MB of image storage free per month.

---

## Infrastructure

All AWS resources are created with Terraform (see `terraform/`). No manual clicking in the console.

| Resource | Service | Purpose |
|---|---|---|
| EC2 t3.micro | EC2 | Runs the Docker container |
| Elastic IP | EC2 | Keeps the public IP stable after restarts |
| Security group | EC2 | Port 80 open, port 22 locked to my IP |
| ECR repository | ECR | Stores Docker images pushed by the pipeline |
| IAM role (EC2) | IAM | Lets the server pull from ECR without storing credentials |
| IAM user (CI) | IAM | GitHub Actions pushes images — ECR push only |
| CloudWatch alarm | CloudWatch | Fires if `/health` stops responding |

---

## Virtual Machine Setup

- **Service:** Amazon EC2
- **Instance type:** t3.micro (1 vCPU, 1 GB RAM) — Free Tier
- **OS:** Ubuntu 22.04 LTS
- **Region:** us-east-1

To provision everything:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# fill in your IP, SSH key path, and optionally alert_email
terraform init
terraform plan
terraform apply
```

Docker and AWS CLI are installed automatically on first boot by `user_data.sh`. No manual steps needed on the server.

---

## How Docker and the image are set up

The pipeline builds the image and pushes it to Amazon ECR tagged with the Git commit SHA. The deploy script on the server then pulls and runs it.

To manually deploy the latest image:

```bash
ssh -i ~/.ssh/id_rsa ubuntu@<EC2_PUBLIC_IP>

# log in to ECR using the server's IAM role
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <ECR_REGISTRY>

docker pull <ECR_REGISTRY>/kora-analytics-api:latest
docker stop kora-api && docker rm kora-api
docker run -d --name kora-api -p 80:3000 -e PORT=3000 \
  --restart unless-stopped \
  <ECR_REGISTRY>/kora-analytics-api:latest
```

---

## Check if the container is running

```bash
# list running containers
docker ps

# check the specific container
docker inspect kora-api --format='Status: {{.State.Status}}'

# test the API locally on the server
curl http://localhost/health
```

---

## View application logs

```bash
# live logs
docker logs -f kora-api

# last 100 lines
docker logs --tail 100 kora-api
```

---

## Bonus 1 — Terraform

All resources (EC2, ECR, IAM, security group, CloudWatch alarm) are defined in `terraform/main.tf`. This makes the setup reproducible and easy to tear down.

To remove everything:

```bash
terraform destroy
```

---

## Bonus 2 — CloudWatch Alarm

A cron job is set up on the EC2 server by `user_data.sh`. It runs every minute, calls `GET /health`, and sends a result to CloudWatch — `1` if the app responded with 200, `0` if not.

The Terraform alarm `kora-api-health-check` watches this metric and fires if it sees two consecutive `0` values (meaning the app has been down for at least 2 minutes).

If `alert_email` is set in `terraform.tfvars`, an email is sent when the alarm triggers or clears.

To view the alarm: **AWS Console → CloudWatch → Alarms**

To view the raw metric: **CloudWatch → Metrics → KoraAnalytics → HealthCheckStatus**

To view the cron log on the server:

```bash
tail -f /var/log/health-check.log
```

Free Tier usage: 1 of 10 free custom metrics, 1 of 10 free alarms per month.

---

## Bonus 3 — Rollback

The deploy job in `deploy.yml` saves the currently running image tag before stopping the container. After starting the new container, it waits 15 seconds and checks `/health`. If the check fails, it stops the new container and restarts the old image. The pipeline exits with an error so the failure is visible in GitHub Actions.
