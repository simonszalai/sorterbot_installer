#!/bin/bash

# Update repositories
sudo yum update -y

# Install Docker and Git
sudo yum install docker git -y

# Install Python3 (required for Django user creation outside of the Docker container)
sudo yum install python3 -y

# Download and Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/1.25.5/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

# Make the Docker Compose binary executable
sudo chmod +x /usr/local/bin/docker-compose

# Download Git Large File Storage (used for some static web assets in the repository)
curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.rpm.sh | sudo bash

# Install Git LFS
sudo yum install git-lfs -y
git lfs install

# Install jq to parse output from SSM
sudo yum install jq -y

# Clone SorterBot Control Repository
git clone https://github.com/simonszalai/sorterbot_control.git

# Start Docker service
sudo service docker start

# Add current user to the Docker group
sudo usermod -a -G docker ec2-user

# Create empty .env file so docker-compose doesn't fail
touch sorterbot_control/sbc_server/.env