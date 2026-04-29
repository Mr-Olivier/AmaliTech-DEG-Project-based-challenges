# AWS Setup Guide

Follow these steps once before running `terraform apply` for the first time.

---

## 1. Create an AWS account

1. Go to \*\*
   ** and click **Create an AWS Account\*\*
2. Enter your email, a password, and an account name (e.g. `kora-analytics`)
3. Add a credit or debit card — you won't be charged while staying in the Free Tier
4. Complete the phone verification
5. Choose the **Basic support plan** (free)
6. Sign in to the console at **https://console.aws.amazon.com**

**Free Tier limits for this project:**

- EC2 t2.micro: 750 hours/month free for 12 months (enough for 24/7)
- ECR: 500 MB storage free per month
- CloudWatch: 10 custom metrics and 10 alarms free per month
- Elastic IP: free while attached to a running instance

---

## 2. Create an IAM admin user

Using the root account daily is risky. Create a separate IAM user instead.

1. In the console, search for **IAM** and open it
2. Click **Users → Create user**
3. Set a username (e.g. `admin-yourname`)
4. Check **Provide user access to the AWS Management Console** → set a password
5. Click **Next → Attach policies directly → AdministratorAccess**
6. Click **Create user**
7. Sign out of root and use this IAM user from now on

---

## 3. Generate an SSH key pair

Terraform uploads your **public key** to AWS. Your **private key** stays on your machine.

```bash
# check if you already have one
ls ~/.ssh/id_rsa.pub

# if not, generate one (press Enter to accept defaults)
ssh-keygen -t rsa -b 4096
```

You'll have:

- `~/.ssh/id_rsa` — private key — never share or commit this
- `~/.ssh/id_rsa.pub` — public key — Terraform uploads this to AWS

---

## 4. Install the tools

**AWS CLI:**

```bash
# Linux / Mac
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip awscliv2.zip && sudo ./aws/install
```

Windows: download and run the MSI from `https://aws.amazon.com/cli/`

**Terraform:**

```bash
# Mac
brew install hashicorp/tap/terraform

# Ubuntu / Debian
sudo apt-get install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install terraform
```

Windows: download from `https://developer.hashicorp.com/terraform/downloads`

---

## 5. Configure the AWS CLI

1. In the AWS console → **IAM → Users → your admin user → Security credentials**
2. Click **Create access key → Command Line Interface → Next → Create**
3. Copy the Access Key ID and Secret Access Key

Then run:

```bash
aws configure
# AWS Access Key ID: paste here
# AWS Secret Access Key: paste here
# Default region: us-east-1
# Default output format: json
```

---

## 6. Run Terraform

```bash
cd dev-ops/DeployReady/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

- Set `your_ip` to your public IP — find it at **https://whatismyip.com**
- Set `ssh_public_key_path` to the path of your `.pub` file
- Optionally set `alert_email` to receive CloudWatch alarm emails

Then:

```bash
terraform init     # downloads the AWS provider
terraform plan     # preview what will be created
terraform apply    # type "yes" to create everything (~2 minutes)
```

Copy the outputs — you'll need them for the next step:

```bash
terraform output ec2_public_ip
terraform output github_actions_access_key_id
terraform output -raw github_actions_secret_access_key
```

---

## 7. Add GitHub secrets

Go to your repository → **Settings → Secrets and variables → Actions → New repository secret**

| Secret name             | Value                                                                      |
| ----------------------- | -------------------------------------------------------------------------- |
| `AWS_ACCESS_KEY_ID`     | from `terraform output github_actions_access_key_id`                       |
| `AWS_SECRET_ACCESS_KEY` | from `terraform output -raw github_actions_secret_access_key`              |
| `EC2_HOST`              | from `terraform output ec2_public_ip`                                      |
| `EC2_SSH_KEY`           | the full contents of `~/.ssh/id_rsa` including the header and footer lines |

---

## 8. Wait for the server to finish setting up

The server installs Docker and AWS CLI on first boot — this takes about 3–5 minutes.

You can check progress by SSHing in:

```bash
ssh -i ~/.ssh/id_rsa ubuntu@<EC2_PUBLIC_IP>
tail -f /var/log/cloud-init-output.log
```

Wait until you see the install finish before triggering the pipeline.

---

## 9. Trigger the pipeline

Push any change to `main` inside `dev-ops/DeployReady/`:

```bash
git add .
git commit -m "add containerization and CI/CD"
git push origin main
```

Go to **GitHub → Actions** and watch the pipeline. A successful run shows:

```
✅ Test
✅ Build & Push
✅ Deploy
```

---

## 10. Verify

```bash
curl http://<EC2_PUBLIC_IP>/health
# expected: {"status":"ok"}
```

This is the URL you submit.

---

## Keeping costs at zero

- Run only **one** t2.micro instance at a time
- Don't stop the instance without destroying the Elastic IP (a stopped-but-allocated EIP costs ~$0.005/hr)
- The ECR lifecycle policy auto-expires old images to stay under 500 MB
- After the evaluation, run `terraform destroy` to remove everything
