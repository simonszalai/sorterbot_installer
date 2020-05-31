#!/bin/bash

# Construct script path from script file location
SCRIPT_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

# Create folder for variables if it doesn't exist
mkdir -p $SCRIPT_PATH/variables

# Load .env.prod
source $SCRIPT_PATH/../.env.prod

# Stop on any error
set -e

# Set deployment mode
export MODE=production

# Save aws configure default profile's region to SSM
DEPLOY_REGION=$(aws configure get region)
aws ssm put-parameter --name "DEPLOY_REGION" --value $DEPLOY_REGION --type "String" > /dev/null
echo "DEPLOY_REGION was successfully saved to SSM parameter store."

# Generate random password and save it to file PG_PASS
python3 $SCRIPT_PATH/../utils/generate_password.py PG_PASS
echo "Random password (PG_PASS) was successfully generated."

# Save the contents of PG_PASS as an SSM SecureString parameter
aws ssm put-parameter --name "PG_PASS" --value "$(< $SCRIPT_PATH/variables/PG_PASS)" --type "SecureString" > /dev/null
echo "PG_PASS was successfully saved to SSM parameter store."

# Generate random password and save it to file DJANGO_SECRET
python3 $SCRIPT_PATH/../utils/generate_password.py DJANGO_SECRET
echo "Random password (DJANGO_SECRET) was successfully generated."

# Save the contents of DJANGO_SECRET as an SSM SecureString parameter
aws ssm put-parameter --name "DJANGO_SECRET" --value "$(< $SCRIPT_PATH/variables/DJANGO_SECRET)" --type "SecureString" > /dev/null
echo "DJANGO_SECRET was successfully saved to SSM parameter store."

# Create SSH keypair for EC2, then make it read-only
aws ec2 create-key-pair --key-name sorterbot --query 'KeyMaterial' --output text > ~/.aws/ssh_sorterbot_ec2.pem
chmod 400 ~/.aws/ssh_sorterbot_ec2.pem
echo "SSH keypair created successfully."

# Create Policy, User and Access Key for GitHub Actions
aws iam create-user --user-name GitHubActionUser > /dev/null
POLICY_ARN=$(aws iam create-policy --policy-name GitHubActionPolicy --policy-document file://${PWD}/policies/GitHubActionPolicy.json | jq '.Policy.Arn' | tr -d '["]') > /dev/null
aws iam attach-user-policy --policy-arn $POLICY_ARN --user-name GitHubActionUser > /dev/null
ACCESS_KEY_OUT=$(aws iam create-access-key --user-name GitHubActionUser)

# Set secrets for GitHub Actions
python3 $SCRIPT_PATH/../utils/set_github_secret.py $GITHUB_TOKEN AWS_ACCESS_KEY_ID $ACCESS_KEY_OUT | jq '.AccessKey.AccessKeyId'
python3 $SCRIPT_PATH/../utils/set_github_secret.py $GITHUB_TOKEN AWS_SECRET_ACCESS_KEY $ACCESS_KEY_OUT | jq '.AccessKey.SecretAccessKey'

# Deploy CloudFormation Stack
cdk deploy sorterbot-prod --require-approval never

# Retrieve newly created RDS instance host
postgresHost=$(aws rds describe-db-instances --filters "Name=db-instance-id,Values=sorterbot-postgres" --query "DBInstances[*].Endpoint.Address" --output text)
echo "RDS Instance endpoint address retrieved."

# Construct postgres connection string and save it as an SSM SecureString parameter
PG_CONN="postgresql://postgres:$(< $SCRIPT_PATH/variables/PG_PASS)@${postgresHost}:5432/sorterbot"
aws ssm put-parameter --name "PG_CONN" --value $PG_CONN --type "SecureString" > /dev/null
echo "Postgres connection string created and saved to SSM parameter store."

# Save postgres connection string as GitHub Action
python3 $SCRIPT_PATH/../utils/set_github_secret.py $GITHUB_TOKEN PG_CONN $PG_CONN

# Remove PG_PASS file
rm $SCRIPT_PATH/variables/PG_PASS
echo "PG_PASS file deleted."

# Remove DJANGO_SECRET file
rm $SCRIPT_PATH/variables/DJANGO_SECRET
echo "DJANGO_SECRET file deleted."

# Wait until EC2 is up and running
aws ec2 wait instance-running --filters "Name=tag-value,Values=sorterbot-control-panel-$(< $SCRIPT_PATH/variables/RESOURCE_SUFFIX)"
echo "EC2 instance is running."

# Retrieve newly created EC2 instance host (and remove whitespaces)
PUBLIC_DNS=$(aws ec2 describe-instances --filters "Name=tag-value,Values=sorterbot-control-panel-$(< $SCRIPT_PATH/variables/RESOURCE_SUFFIX)" --query "Reservations[*].Instances[*].PublicDnsName" | jq '.[0][0]' | tr -d '["]')
echo "EC2 Instance DNS is retrieved."

# Install dependencies on EC2 instance
ssh -o "StrictHostKeyChecking no" -i ~/.aws/ssh_sorterbot_ec2.pem ec2-user@$PUBLIC_DNS "bash -s -- uno" < $SCRIPT_PATH/setup_control_panel.sh
echo "EC2 setup complete."

# Create empty .env file so docker-compose doesn't fail
ssh -o "StrictHostKeyChecking no" -i ~/.aws/ssh_sorterbot_ec2.pem ec2-user@$PUBLIC_DNS "touch sorterbot_control/sbc_server/.env"

# Set region as environemnt variable
ssh -o "StrictHostKeyChecking no" -i ~/.aws/ssh_sorterbot_ec2.pem ec2-user@$PUBLIC_DNS "export DEPLOY_REGION=$DEPLOY_REGION"

# Build Docker image then start Docker Compose
ssh -o "StrictHostKeyChecking no" -i ~/.aws/ssh_sorterbot_ec2.pem ec2-user@$PUBLIC_DNS "docker build -t sorterbot_control:latest sorterbot_control; cd sorterbot_control; EXT_PORT=80 MODE=production MIGRATE=1 docker-compose up"

# Set Django password as environment variable on the EC2 instance
ssh -o "StrictHostKeyChecking no" -i ~/.aws/ssh_sorterbot_ec2.pem ec2-user@$PUBLIC_DNS "export DJANGO_SUPERUSER_PASSWORD=$2"

# Install requirements so Django manage.py can be run outside Docker container
ssh -o "StrictHostKeyChecking no" -i ~/.aws/ssh_sorterbot_ec2.pem ec2-user@$PUBLIC_DNS "sudo pip3 install -r sorterbot_control/sbc_server/requirements.txt"

# Create Django superuser
ssh -o "StrictHostKeyChecking no" -i ~/.aws/ssh_sorterbot_ec2.pem ec2-user@$PUBLIC_DNS "\
    DEPLOY_REGION=$DEPLOY_REGION \
    MODE=production \
    python3 sorterbot_control/sbc_server/manage.py createsuperuser --username $1 --email blank@email.com --noinput \
"

# Collect static files and host them on S3
ssh -o "StrictHostKeyChecking no" -i ~/.aws/ssh_sorterbot_ec2.pem ec2-user@$PUBLIC_DNS "MODE=production python3 sorterbot_control/sbc_server/manage.py collectstatic --noinput"

# =================== Provide neccessary permissions to EC2 Instance by assigning an Instance Profile ===================
# Create Role
aws iam create-role --role-name SorterBotControlRoleProd --assume-role-policy-document file://policies/SorterBotControlAssumePolicy.json > /dev/null

# Get SorterBotControlPolicyProd ARN
CONTROL_POLICY_ARN=$(aws iam list-policies --query 'Policies[?PolicyName==`SorterBotControlPolicyProd`]' | jq '.[0].Arn' | tr -d '["]')

# Attach Policy to Role
aws iam attach-role-policy --policy-arn $CONTROL_POLICY_ARN --role-name SorterBotControlRoleProd > /dev/null

# Create Instance Profile
aws iam create-instance-profile --instance-profile-name SorterBotInstanceProfile > /dev/null

# Add Policy to Instance Profile
aws iam add-role-to-instance-profile --role-name SorterBotControlRoleProd --instance-profile-name SorterBotInstanceProfile

# Get Instance Profile - EC2 Instance association ID
ASSOC_ID=$(aws ec2 describe-iam-instance-profile-associations | jq '.IamInstanceProfileAssociations[0].AssociationId' | tr -d '["]')

# Replace automatically assigned Instance Profile with existing one
aws ec2 replace-iam-instance-profile-association --association-id $ASSOC_ID --iam-instance-profile Name=SorterBotInstanceProfile