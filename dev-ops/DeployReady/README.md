# Kora Analytics API

A Node.js REST API containerised with Docker, deployed to AWS EC2 through a GitHub Actions pipeline, and monitored with CloudWatch.

---

## How it works

```
Push to main
     │
     ▼
GitHub Actions
  1. npm test          → stops here if any test fails
  2. docker build      → pushes image to Amazon ECR (tagged with commit SHA)
  3. ssh deploy        → pulls new image on EC2, restarts container, checks /health
                         → rolls back to the previous image if /health fails

EC2 t3.micro (Ubuntu 22.04, us-east-1)
  └─ Docker container on port 80
       ├─ GET  /health   → { "status": "ok" }
       ├─ GET  /metrics  → uptime and memory stats
       └─ POST /data     → echoes the JSON body back

CloudWatch
  └─ cron job runs every 60s → hits /health → sends 1 or 0 to CloudWatch
     alarm fires if 0 appears twice in a row (2 minutes of downtime)
```

---

## Project structure

```
DeployReady/
├── app/                  Node.js Express app (not modified)
├── terraform/            All AWS infrastructure as code
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── user_data.sh      installs Docker, AWS CLI, and health-check cron on boot
│   └── terraform.tfvars.example
├── .github/workflows/
│   └── deploy.yml        CI/CD pipeline
├── Dockerfile
├── docker-compose.yml
├── .env.example
├── DEPLOYMENT.md         infrastructure docs and bonus writeup
└── AWS_SETUP.md          step-by-step guide to set up AWS and deploy
```

---

## Run locally

```bash
cp .env.example .env
docker compose up --build

curl http://localhost:3000/health
# { "status": "ok" }
```

Run the tests:

```bash
cd app && npm install && npm test
```

---

## Deploy to AWS

See **`AWS_SETUP.md`** for the full walkthrough. The short version:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# fill in: your_ip, ssh_public_key_path, and optionally alert_email

terraform init && terraform apply
```

Then add the four outputs as GitHub repository secrets (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `EC2_HOST`, `EC2_SSH_KEY`) and push to `main`.

---

## AWS resources (all Free Tier)

| Resource | Free Tier |
|---|---|
| EC2 t3.micro | 750 h/month for 12 months |
| Elastic IP | free while attached to a running instance |
| ECR | 500 MB/month |
| CloudWatch alarm | 10 alarms/month free |
| CloudWatch metric | 10 custom metrics/month free |
| IAM, security groups | always free |

---

## Design decisions

**node:20-alpine** — smallest official Node image; keeps the ECR image under 200 MB.

**Non-root container user** — running as root inside a container is a security risk even if the container is isolated.

**ECR over Docker Hub** — native AWS IAM integration means the EC2 server can pull images using its role, with no credentials stored on disk.

**Terraform** — all infrastructure is defined in one file and can be recreated or destroyed with a single command.

**Rollback** — the deploy script saves the current image tag before swapping containers. If `/health` fails after the new container starts, the old one is brought back automatically.

**CloudWatch custom metric** — a standard EC2 status check only tells you if the instance is alive. The cron-based custom metric actually tests the HTTP endpoint, so a crashed container triggers the alarm even while the instance is still running.

---

## Submission checklist

- [x] `docker compose up --build` starts the app
- [x] `.env.example` committed, real `.env` gitignored
- [x] Pipeline: test → build → push → deploy (stops on failure)
- [x] All secrets stored in GitHub repository secrets
- [x] SSH port 22 not open to `0.0.0.0/0`
- [x] `DEPLOYMENT.md` covers VM setup, Docker, container check, and logs
- [x] Bonus: Terraform provisions all infrastructure
- [x] Bonus: CloudWatch alarm triggers if `/health` stops responding
- [x] Bonus: Pipeline rolls back automatically on health check failure
- [ ] At least one successful pipeline run visible in GitHub Actions
- [ ] `GET http://<EC2_PUBLIC_IP>/health` returns `{"status":"ok"}`
