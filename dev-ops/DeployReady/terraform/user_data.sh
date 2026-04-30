#!/bin/bash
# First-boot setup: installs Docker, AWS CLI v2, and a CloudWatch health-check cron job.
set -euo pipefail

apt-get update -y
apt-get install -y ca-certificates curl gnupg unzip

# Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# AWS CLI v2
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/aws /tmp/awscliv2.zip

# runs every minute, pushes 1 (up) or 0 (down) to CloudWatch
cat > /usr/local/bin/health-check.sh << 'SCRIPT'
#!/bin/bash
RESULT=0
if curl -sf --max-time 5 http://localhost/health > /dev/null 2>&1; then
  RESULT=1
fi
aws cloudwatch put-metric-data \
  --namespace "KoraAnalytics" \
  --metric-name "HealthCheckStatus" \
  --value "$RESULT" \
  --unit "None" \
  --region "us-east-1"
SCRIPT

chmod +x /usr/local/bin/health-check.sh

echo "* * * * * ubuntu /usr/local/bin/health-check.sh >> /var/log/health-check.log 2>&1" \
  > /etc/cron.d/kora-health-check
chmod 644 /etc/cron.d/kora-health-check
