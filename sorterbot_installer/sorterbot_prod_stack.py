import os
from aws_cdk import (
    core,
    aws_s3 as s3,
    aws_ec2 as ec2,
    aws_ecs as ecs,
    aws_ecr as ecr,
    aws_rds as rds,
    aws_iam as iam,
    aws_ssm as ssm
)


class SorterBotProdStack(core.Stack):
    def __init__(self, scope, id, **kwargs):
        super().__init__(scope, id, **kwargs)


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

        sg_control = ec2.SecurityGroup(
            self,
            "sorterbot-control-sg",
            vpc=vpc,
            allow_all_outbound=True,
            security_group_name="sorterbot-control-sg"
        )
        sg_control.add_ingress_rule(ec2.Peer.any_ipv4(), ec2.Port.tcp(22))
        sg_control.add_ingress_rule(ec2.Peer.any_ipv4(), ec2.Port.tcp(5432))
        sg_control.add_ingress_rule(ec2.Peer.any_ipv4(), ec2.Port.tcp(80))


        # ====================================== IAM ======================================
        # Create IAM roles
        cloud_role = iam.Role(
            self,
            "sorterbotCloudRole",
            assumed_by=iam.ServicePrincipal('ecs.amazonaws.com'),
            role_name="sorterbotCloudRole",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonS3FullAccess"),
                iam.ManagedPolicy.from_managed_policy_arn(
                    self,
                    "sorterbotAmazonECSTaskExecutionRolePolicy",
                    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
                ),
            ]
        )

        # Create IAM policies
        secrets_for_ECS_policy = iam.ManagedPolicy(
            self,
            "sorterbotSecretsForECSPolicy",
            managed_policy_name="sorterbotSecretsForECSPolicy",
            roles=[cloud_role],
            statements=[
                iam.PolicyStatement(resources=["*"], actions=[
                    "ssm:GetParameters",
                    "secretsmanager:GetSecretValue",
                    "kms:Decrypt"
                ])
            ]
        )

        # ====================================== S3 ======================================
        # Create S3 bucket
        s3.Bucket(self, "sorterbot", bucket_name="sorterbot", removal_policy=core.RemovalPolicy.DESTROY)
        s3.Bucket(self, "sorterbot-static", bucket_name="sorterbot-static", removal_policy=core.RemovalPolicy.DESTROY)

        # ====================================== EC2 ======================================
        # Create EC2 instance for Control Panel
        control_panel_instance = ec2.Instance(
            self,
            "sorterbot-control-panel",
            instance_name="sorterbot-control-panel",
            instance_type=ec2.InstanceType("t2.micro"),
            machine_image=ec2.MachineImage.latest_amazon_linux(generation=ec2.AmazonLinuxGeneration.AMAZON_LINUX_2),
            vpc=vpc,
            key_name="sorterbot",
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC),
            security_group=sg_control
        )

        control_panel_instance.add_to_role_policy(iam.PolicyStatement(
            resources=["*"],
            actions=[
                "ec2:DescribeNetworkInterfaces",
                "ssm:GetParameter",
                "ecs:*",
                "s3:*"
            ]
        ))

        # ====================================== RDS ======================================
        # Declare connection details
        master_username = "postgres"
        master_user_password = core.SecretValue.ssm_secure("PG_PASS", version="1")
        port = 5432

        # Create postgres database
        database = rds.DatabaseInstance(
            self,
            "sorterbot_postgres",
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


        # ====================================== ECR ======================================
        # Create ECR repository for Docker images
        ecr.Repository(self, "sorterbot-ecr", repository_name="sorterbot-ecr", removal_policy=core.RemovalPolicy.DESTROY)


        # ====================================== ECS ======================================
        # Create ECS Cluster, Task Definition and Fargate Service
        ecs_cluster = ecs.Cluster(self, "sorterbot-ecs-cluster", vpc=vpc, cluster_name="sorterbot-ecs-cluster")
        task_definition = ecs.FargateTaskDefinition(self, "sorterbot-fargate-service", cpu=512, memory_limit_mib=4096)
        task_definition.add_container("sorterbot-cloud-container", image=ecs.ContainerImage.from_registry("amazon/amazon-ecs-sample"))
        ecs.FargateService(
            self,
            "sorterbot-ecs-service",
            cluster=ecs_cluster,
            task_definition=task_definition,
            assign_public_ip=True,
            service_name="sorterbot-ecs-service",
            desired_count=0
        )
