#!/bin/bash

# Stop on any error
set -e

# Set deployment mode
export MODE=development

# Construct script path from script file location
SCRIPT_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

# Create folder for variables if it doesn't exist
mkdir -p $SCRIPT_PATH/variables

# Generate random password for postgres and save it to file PG_PASS
python3 $SCRIPT_PATH/../utils/generate_password.py PG_PASS
echo "Random password (PG_PASS) was successfully generated."

# Save the contents of PG_PASS as an SSM SecureString parameter
aws ssm put-parameter --name "PG_PASS" --value "$(< $SCRIPT_PATH/variables/PG_PASS)" --type "SecureString" > /dev/null
echo "PG_PASS was successfully saved to SSM parameter store."

# Deploy CloudFormation Stack
MODE=production cdk deploy sorterbot-dev --require-approval never

# Retrieve newly created RDS instance host
postgresHost=$(aws rds describe-db-instances --filters "Name=db-instance-id,Values=sorterbot-postgres" --query "DBInstances[*].Endpoint.Address" --output text)
echo "RDS Instance endpoint address retrieved."

# Construct postgres connection string and save it as an SSM SecureString parameter
PG_CONN="postgresql://postgres:$(< PG_PASS)@${postgresHost}:5432/sorterbot"
aws ssm put-parameter --name "PG_CONN" --value $PG_CONN --type "SecureString" > /dev/null
echo "Postgres connection string created and saved to SSM parameter store."

# Remove PG_PASS file
rm $SCRIPT_PATH/variables/PG_PASS
echo "PG_PASS file deleted."
