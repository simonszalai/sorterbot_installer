#!/bin/bash

# Construct script path from script file location
SCRIPT_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

# Delete S3 buckets even if they contain files
aws s3 rb s3://sorterbot-$(< $SCRIPT_PATH/variables/RESOURCE_SUFFIX) --force
aws s3 rb s3://sorterbot-static-$(< $SCRIPT_PATH/variables/RESOURCE_SUFFIX) --force

# Delete ECR repository even if it contains images
aws ecr delete-repository --repository-name sorterbot-ecr --force > /dev/null