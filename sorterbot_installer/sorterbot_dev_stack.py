"""
CloudFormation stack to deploy the resources needed for `aws-dev` development mode.

"""

import random
import string
from pathlib import Path
from aws_cdk import (
    core,
    aws_s3 as s3,
    aws_ec2 as ec2,
    aws_rds as rds,
    aws_ssm as ssm
)


class SorterBotDevStack(core.Stack):
    def __init__(self, scope, id, **kwargs):
        super().__init__(scope, id, **kwargs)

        # Create random string to be used as suffix on some resource names
        resource_suffix = ''.join(random.choice(string.ascii_lowercase) for i in range(8))

        # Save it as SSM parameter to be used in runtime
        ssm.StringParameter(self, "RESOURCE_SUFFIX", string_value=resource_suffix, parameter_name="RESOURCE_SUFFIX")

        # Save it to disk to be used when destroying
        with open(Path(__file__).parents[1].joinpath("scripts", "variables", "RESOURCE_SUFFIX"), "w") as outfile:
            outfile.write(resource_suffix)


        # ====================================== VPC ======================================
        # Create VPC
        vpc = ec2.Vpc(
            self,
            "sorterbot-vpc",
            cidr="10.0.0.0/16",
            enable_dns_support=True,
            enable_dns_hostnames=True,
            max_azs=2,
            nat_gateways=0,
            subnet_configuration=[
                {
                    "subnetType": ec2.SubnetType.PUBLIC,
                    "name": "sorterbot-public-subnet-a",
                    "cidrMask": 24,
                },
                {
                    "subnetType": ec2.SubnetType.PUBLIC,
                    "name": "sorterbot-public-subnet-b",
                    "cidrMask": 24,
                },
            ]
        )

        # Create security groups
        sg_vpc = ec2.SecurityGroup(
            self,
            "sorterbot-vpc-sg",
            vpc=vpc,
            allow_all_outbound=True,
            security_group_name="sorterbot-vpc-sg"
        )
        sg_vpc.add_ingress_rule(sg_vpc, ec2.Port.all_traffic())

        # ====================================== S3 ======================================
        # Create S3 bucket
        s3.Bucket(self, f"sorterbot-{resource_suffix}", bucket_name=f"sorterbot-{resource_suffix}", removal_policy=core.RemovalPolicy.DESTROY)


        # ====================================== RDS ======================================
        # Declare connection details
        master_username = "postgres"
        master_user_password = core.SecretValue.ssm_secure("PG_PASS", version="1")
        port = 5432

        # Create postgres database
        database = rds.DatabaseInstance(
            self,
            "sorterbot-postgres",
            allocated_storage=10,
            backup_retention=core.Duration.days(0),  # Don't save backups since storing them is not covered by the Free Tier
            database_name="sorterbot",
            delete_automated_backups=True,
            deletion_protection=False,
            engine=rds.DatabaseInstanceEngine.POSTGRES,
            engine_version="11",
            instance_class=ec2.InstanceType("t2.micro"),  # Stay in Free Tier
            instance_identifier="sorterbot-postgres",
            master_username=master_username,
            master_user_password=master_user_password,
            port=port,
            storage_type=rds.StorageType.GP2,
            vpc=vpc,
            vpc_placement=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC),  # Make DB publicly accessible (with credentials)
            removal_policy=core.RemovalPolicy.DESTROY
        )

        # Add ingress rule to allow external connections
        database.connections.allow_default_port_from_any_ipv4()
