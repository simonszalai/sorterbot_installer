#!/bin/bash

# Delete SSM parameters
aws ssm delete-parameter --name "PG_PASS" > /dev/null
aws ssm delete-parameter --name "PG_CONN" > /dev/null
echo "SSM parameters deleted successfully."

# Destroy AWS resources
PROJECT_NAME=$1 MODE=development cdk destroy sorterbot-dev -f