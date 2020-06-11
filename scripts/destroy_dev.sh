#!/bin/bash

# Delete SSM parameters
aws ssm delete-parameter --name "PG_PASS" > /dev/null
aws ssm delete-parameter --name "PG_CONN" > /dev/null
aws ssm delete-parameter --name "DJANGO_SECRET" > /dev/null
aws ssm delete-parameter --name "DEPLOY_REGION" > /dev/null
echo "SSM parameters deleted successfully."

# Destroy AWS resources
MODE=development cdk destroy sorterbot-dev -f