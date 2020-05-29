#!/bin/bash

# Delete SSM parameters
aws ssm delete-parameter --name "PG_PASS" > /dev/null
aws ssm delete-parameter --name "PG_CONN" > /dev/null
echo "SSM parameters deleted successfully."

# Delete SSH keypair
chmod 777 "~/.aws/ssh_$1_ec2.pem"
rm "~/.aws/ssh_$1_ec2.pem"
aws ec2 delete-key-pair --key-name $1 > /dev/null
echo "SSH keypair deleted successfully."

# Destroy AWS resources
PROJECT_NAME=$1 cdk destroy -f