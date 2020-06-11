#!/bin/bash

# Construct script path from script file location
SCRIPT_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

# Load .env.prod
source $SCRIPT_PATH/../.env.prod

# Retrieve default profile's region
export DEPLOY_REGION=$(aws configure get region)

# Delete SSM parameters
aws ssm delete-parameter --name "PG_PASS" > /dev/null
aws ssm delete-parameter --name "PG_CONN" > /dev/null
aws ssm delete-parameter --name "DJANGO_SECRET" > /dev/null
aws ssm delete-parameter --name "DEPLOY_REGION" > /dev/null
echo "SSM parameters deleted successfully."

# Delete SSH keypair
chmod 777 ~/.aws/ssh_sorterbot_ec2.pem
rm ~/.aws/ssh_sorterbot_ec2.pem
aws ec2 delete-key-pair --key-name sorterbot > /dev/null
echo "SSH keypair deleted successfully."

# Detach user policy to enable user delete
# GITHUB_POLICY_ARN=$(aws iam list-policies --query 'Policies[?PolicyName==`GitHubActionPolicy`]' | jq '.[0].Arn' | tr -d '["]')

# Delete IAM policies
# aws iam detach-user-policy --user-name GitHubActionUser --policy-arn $GITHUB_POLICY_ARN  > /dev/null
aws iam detach-user-policy --user-name GitHubActionUser --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/GitHubActionPolicy  > /dev/null
aws iam delete-policy --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/GitHubActionPolicy > /dev/null

aws iam detach-role-policy --role-name SorterBotCloudRole --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/SorterBotSecretsForECSPolicy  > /dev/null
aws iam delete-policy --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/SorterBotSecretsForECSPolicy > /dev/null
echo "IAM policies deleted successfully."

# Delete access key to enable user delete
aws iam delete-access-key --access-key-id $(aws iam list-access-keys --user-name GitHubActionUser --query 'AccessKeyMetadata[0].AccessKeyId' | tr -d '["]') --user-name GitHubActionUser > /dev/null

# Delete IAM user
aws iam delete-user --user-name GitHubActionUser > /dev/null
echo "IAM user deleted successfully."

# Delete SorterBotSecretsForECSPolicy as CDK fails to remove the role that depends on it
# aws iam detach-role-policy
# aws iam delete-policy --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/SorterBotSecretsForECSPolicy > /dev/null
# aws iam delete-role --role-name SorterBotCloudRole > /dev/null

# Destroy AWS resources
MODE=production cdk destroy sorterbot-prod -f
