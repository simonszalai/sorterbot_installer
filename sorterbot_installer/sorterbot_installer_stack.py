import os
from aws_cdk import (
    core,
    aws_s3 as s3,
    aws_ec2 as ec2,
    aws_ecs as ecs,
    aws_ecr as ecr,
    aws_rds as rds
)


class SorterbotInstallerStack(core.Stack):
    def __init__(self, scope, id, **kwargs):
        super().__init__(scope, id, **kwargs)

        # Create S3 buckets
        s3.Bucket(self, "asorterbot", bucket_name="asorterbot")
        s3.Bucket(self, "asorterbot-datasets", bucket_name="asorterbot-datasets")
        s3.Bucket(self, "asorterbot-videos", bucket_name="asorterbot-videos")
        s3.Bucket(self, "asorterbot-weights", bucket_name="asorterbot-weights")

        # Create VPC
        vpc = ec2.Vpc(
            self,
            "sorterbot-vpc",
            cidr="10.0.0.0/16",
            enable_dns_hostnames=True,
            max_azs=2,
            natGateways=0,
            subnetConfiguration=[
                {
                    "subnetType": ec2.SubnetType.PUBLIC,
                    "name": 'sorterbot-public-subnet-a',
                    "cidrMask": 24,
                },
                {
                    "subnetType": ec2.SubnetType.PUBLIC,
                    "name": 'sorterbot-public-subnet-b',
                    "cidrMask": 24,
                },
            ]
        )

        # Create security group for VPC to allow incoming connections
        sg = ec2.SecurityGroup(
            self,
            "sorterbot-sg",
            vpc=vpc,
            allow_all_outbound=True,
            security_group_name="sorterbot-sg"
        )
        sg.add_ingress_rule(sg, ec2.Port.all_traffic())

        # Create postgres database
        rds.DatabaseInstance(
            self,
            "asorterbot_postgres",
            allocated_storage=10,
            backup_retention=core.Duration.days(0),  # Don't save backups since storing them is not covered by the Free Tier
            database_name="sorterbot",
            delete_automated_backups=True,
            deletion_protection=False,
            engine=rds.DatabaseInstanceEngine.POSTGRES,
            engine_version="11",
            instance_class=ec2.InstanceType("t2.micro"),  # Stay in Free Tier
            instance_identifier="asorterbot-postgres",
            master_username="postgres",
            storage_type=rds.StorageType.GP2,
            vpc=vpc,
            vpc_placement=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC)  # Make DB publicly accessible (with credentials)
        )

        # Create ECR repository for Docker images
        ecr.Repository(self, "asorterbot-ecr", repository_name="asorterbot-ecr")

        # Create ECS Cluster, Task Definition and Fargate Service
        ecs_cluster = ecs.Cluster(self, "asorterbot-ecs-cluster", vpc=vpc, cluster_name="asorterbot-ecs-cluster")
        task_definition = ecs.FargateTaskDefinition(self, "asorterbot-fargate-service", cpu=512, memory_limit_mib=4096)
        task_definition.add_container("asorterbot-cloud-container", image=ecs.ContainerImage.from_registry("amazon/amazon-ecs-sample"))
        ecs.FargateService(
            self,
            "asorterbot-ecs-service",
            cluster=ecs_cluster,
            task_definition=task_definition,
            assign_public_ip=True,
            service_name="asorterbot-ecs-service",
            desired_count=0
        )

        # os.environ["AWS_ACCESS_KEY_ID"] = ""
        # os.environ["AWS_SECRET_ACCESS_KEY"] = ""
