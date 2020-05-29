### Deploy SorterBot to AWS

#### Install Dependencies
1. Install (jq)[https://stedolan.github.io/jq/download/]

1. Create an SSH keypair that can be used to connect to you EC2 instance that will be created later. Run the following command in the terminal:
    ```
    aws ec2 create-key-pair --key-name sorterbot --query 'KeyMaterial' --output text > ~/.aws/ssh_sorterbot_ec2.pem
    ```
1. Deploy the SorterBot Installer stack to AWS:
    ```
    cdk deploy
    ```
1. SSH to your newly created EC2 instance using the keypair created earlier:
    ```
    chmod 400 ~/.aws/ssh_sorterbot_ec2.pem
    ssh -o "StrictHostKeyChecking no" -i ~/.aws/ssh_sorterbot_ec2.pem ec2-user@[EC2_PUBLIC_DNS]
    ```



1. Upload the postgres connection string as an SSM Parameter
```
aws ssm put-parameter --name "SorterBotCloudPostgres" --value "P@sSwW)rd" --type "SecureString"
```