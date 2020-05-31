#!/bin/bash

SCRIPT_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

# Load .env.prod
source $SCRIPT_PATH/../.env.prod

# Stop on any error
set -e

# Set deployment mode
export MODE=production

# Generate random password and save it to file PG_PASS
python3 ../utils/generate_password.py PG_PASS
echo "Random password (PG_PASS) was successfully generated."

# Save the contents of PG_PASS as an SSM SecureString parameter
aws ssm put-parameter --name "PG_PASS" --value "$(< PG_PASS)" --type "SecureString" > /dev/null
echo "PG_PASS was successfully saved to SSM parameter store."

# Generate random password and save it to file DJANGO_SECRET
python3 ../utils/generate_password.py DJANGO_SECRET
echo "Random password (DJANGO_SECRET) was successfully generated."

# Save the contents of DJANGO_SECRET as an SSM SecureString parameter
aws ssm put-parameter --name "DJANGO_SECRET" --value "$(< DJANGO_SECRET)" --type "SecureString" > /dev/null
echo "DJANGO_SECRET was successfully saved to SSM parameter store."

# Create SSH keypair for EC2, then make it read-only
aws ec2 create-key-pair --key-name sorterbot --query 'KeyMaterial' --output text > ~/.aws/ssh_sorterbot_ec2.pem
chmod 400 ~/.aws/ssh_sorterbot_ec2.pem
echo "SSH keypair created successfully."

# Create Policy, User and Access Key for GitHub Actions
aws iam create-user --user-name GitHubActionUser
POLICY_ARN=$(aws iam create-policy --policy-name GitHubActionPolicy4 --policy-document file://${PWD}/policies/GitHubActionPolicy.json | jq '.Policy.Arn')
aws iam attach-user-policy --policy-arn $POLICY_ARN --user-name GitHubActionUser
ACCESS_KEY_OUT=aws iam create-access-key --user-name GitHubActionUser

# Set secrets for GitHub Actions
python3 ../utils/set_github_secret.py $GITHUB_TOKEN AWS_ACCESS_KEY_ID $ACCESS_KEY_OUT | jq '.AccessKey.AccessKeyId'
python3 ../utils/set_github_secret.py $GITHUB_TOKEN AWS_SECRET_ACCESS_KEY $ACCESS_KEY_OUT | jq '.AccessKey.SecretAccessKey'

# Deploy CloudFormation Stack
PROJECT_NAME=sorterbot cdk deploy SorterBotProdStack --require-approval never

# Retrieve newly created RDS instance host
postgresHost=$(aws rds describe-db-instances --filters "Name=db-instance-id,Values=sorterbot-postgres" --query "DBInstances[*].Endpoint.Address" --output text)
echo "RDS Instance endpoint address retrieved."

# Construct postgres connection string and save it as an SSM SecureString parameter
PG_CONN="postgresql://postgres:$(< PG_PASS)@${postgresHost}:5432/sorterbot"
aws ssm put-parameter --name "PG_CONN" --value $PG_CONN --type "SecureString" > /dev/null
echo "Postgres connection string created and saved to SSM parameter store."

# Save postgres connection string as GitHub Action
python3 ../utils/set_github_secret.py $GITHUB_TOKEN PG_CONN $PG_CONN

# Remove PG_PASS file
rm PG_PASS
echo "PG_PASS file deleted."

# Remove DJANGO_SECRET file
rm DJANGO_SECRET
echo "DJANGO_SECRET file deleted."

# Wait until EC2 is up and running
aws ec2 wait instance-running --filters "Name=tag-value,Values=sorterbot-control-panel"
echo "EC2 instance is running."

# Retrieve newly created EC2 instance host (and remove whitespace)
publicDns=$(aws ec2 describe-instances --filters "Name=tag-value,Values=sorterbot-control-panel" --query "Reservations[*].Instances[*].PublicDnsName" --output text)
publicDns="$(echo -e "${publicDns}" | tr -d '[:space:]')"
echo "EC2 Instance DNS is retrieved."

# Install dependencies on EC2 instance
ssh -o "StrictHostKeyChecking no" -i ~/.aws/ssh_sorterbot_ec2.pem ec2-user@"${publicDns}" "bash -s -- uno" < setup_control_panel.sh
echo "EC2 setup complete."

# Build Docker image than start Docker Compose
ssh -o "StrictHostKeyChecking no" -i ~/.aws/ssh_sorterbot_ec2.pem ec2-user@"${publicDns}" "docker build -t sorterbot_control:latest sorterbot_control; cd sorterbot_control; EXT_PORT=80 DISABLE_AWS=0 MIGRATE=1 docker-compose up"

# Set Django password as environment variable on the EC2 instance
ssh -o "StrictHostKeyChecking no" -i ~/.aws/ssh_sorterbot_ec2.pem ec2-user@"${publicDns}" "export DJANGO_SUPERUSER_PASSWORD=$3"
ssh -o "StrictHostKeyChecking no" -i ~/.aws/ssh_sorterbot_ec2.pem ec2-user@"${publicDns}" "sudo pip3 install -r sorterbot_control/sbc_server/requirements.txt"
ssh -o "StrictHostKeyChecking no" -i ~/.aws/ssh_sorterbot_ec2.pem ec2-user@"${publicDns}" "python3 sorterbot_control/sbc_server/manage.py createsuperuser --username $2 --email blank@email.com"

# Collect static files and host them on S3
ssh -o "StrictHostKeyChecking no" -i ~/.aws/ssh_sorterbot_ec2.pem ec2-user@"${publicDns}" "python3 sorterbot_control/sbc_server/manage.py collectstatic
