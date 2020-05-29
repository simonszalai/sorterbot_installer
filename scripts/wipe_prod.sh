#!/bin/bash

# Delete S3 buckets even if they contain files
aws s3 rb s3://sorterbot --force
aws s3 rb s3://sorterbot-static --force

# Delete ECR repository even if it contains images
aws ecr delete-repository --repository-name sorterbot-ecr --force > /dev/null