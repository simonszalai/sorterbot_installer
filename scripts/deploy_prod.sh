#!/bin/bash

# Stop on any error
set -e

# Construct script path from script file location
SCRIPT_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

# Create folder for variables if it doesn't exist
mkdir -p $SCRIPT_PATH/variables

# Load .env.prod
source $SCRIPT_PATH/../.env.prod

# Set deployment mode
export MODE=production

# Retrieve default profile's region
export DEPLOY_REGION=$(aws configure get region)

# Set custom weights URL
export WEIGHTS_URL=""

# Save aws configure default profile's region to SSM
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
python3 $SCRIPT_PATH/../utils/set_github_secret.py $GITHUB_TOKEN AWS_ACCESS_KEY_ID $(echo $ACCESS_KEY_OUT | jq '.AccessKey.AccessKeyId' | tr -d '["]')
python3 $SCRIPT_PATH/../utils/set_github_secret.py $GITHUB_TOKEN AWS_SECRET_ACCESS_KEY $(echo $ACCESS_KEY_OUT | jq '.AccessKey.SecretAccessKey' | tr -d '["]')

# Save parameters as secrets for GitHub Actions
python3 $SCRIPT_PATH/../utils/set_github_secret.py $GITHUB_TOKEN DEPLOY_REGION $DEPLOY_REGION
python3 $SCRIPT_PATH/../utils/set_github_secret.py $GITHUB_TOKEN WEIGHTS_URL $WEIGHTS_URL

# Deploy CloudFormation Stack
cdk deploy sorterbot-prod --require-approval never

# Upload model weights to S3
# aws s3 cp $SCRIPT_PATH/.. s3://my-bucket/

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

# Set region as environemnt variable
ssh -o "StrictHostKeyChecking no" -i ~/.aws/ssh_sorterbot_ec2.pem ec2-user@$PUBLIC_DNS "export DEPLOY_REGION=$DEPLOY_REGION"

# Build Docker image
ssh -o "StrictHostKeyChecking no" -i ~/.aws/ssh_sorterbot_ec2.pem ec2-user@$PUBLIC_DNS " \
    docker build \
        --build-arg MODE_ARG=production \
        --build-arg DEPLOY_REGION_ARG=$DEPLOY_REGION \
        --build-arg RESOURCE_SUFFIX_ARG=$(< $SCRIPT_PATH/variables/RESOURCE_SUFFIX) \
        -t sorterbot_control:latest sorterbot_control; \
"

# Install requirements so Django manage.py can be run outside Docker container (in order to avoid using password as a build argument, as it shows up in the logs)
ssh -o "StrictHostKeyChecking no" -i ~/.aws/ssh_sorterbot_ec2.pem ec2-user@$PUBLIC_DNS "sudo pip3 install -r sorterbot_control/sbc_server/requirements.txt"

# Run Django migrations
ssh -o "StrictHostKeyChecking no" -i ~/.aws/ssh_sorterbot_ec2.pem ec2-user@$PUBLIC_DNS " \
    DEPLOY_REGION=$DEPLOY_REGION MODE=production python3 sorterbot_control/sbc_server/manage.py makemigrations \
"
ssh -o "StrictHostKeyChecking no" -i ~/.aws/ssh_sorterbot_ec2.pem ec2-user@$PUBLIC_DNS " \
    DEPLOY_REGION=$DEPLOY_REGION MODE=production python3 sorterbot_control/sbc_server/manage.py migrate \
"

# Create Django superuser
ssh -o "StrictHostKeyChecking no" -i ~/.aws/ssh_sorterbot_ec2.pem ec2-user@$PUBLIC_DNS "\
    DEPLOY_REGION=$DEPLOY_REGION \
    DJANGO_SUPERUSER_PASSWORD=$DJANGO_SUPERUSER_PASSWORD \
    MODE=production \
    python3 sorterbot_control/sbc_server/manage.py createsuperuser --username $DJANGO_USER --email blank@email.com --noinput \
"

# Create a release on GitHub to start the CI pipeline
curl -v -i -X POST \
    -H "Content-Type:application/json" \
    -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/${GITHUB_USER}/sorterbot_cloud/releases" \
    -d '{"tag_name": "'$1'", "target_commitish": "master"}' > /dev/null

# Start docker-compose in background
ssh -o "StrictHostKeyChecking no" -i ~/.aws/ssh_sorterbot_ec2.pem ec2-user@$PUBLIC_DNS "EXT_PORT=80 MODE=production DEPLOY_REGION=$DEPLOY_REGION docker-compose -f sorterbot_control/docker-compose.yml up -d"

echo "GitHub Action triggered to deploy SorterBot Cloud to AWS ECS. Please allow ~15 minutes for the workflow to complete."
echo "SorterBot Control Panel is online, you can log in here: ${PUBLIC_DNS}"