#!/bin/bash

set -e

# Authenticate with AWS using gp idp login aws
if ! gp idp login aws --role-arn arn:aws:iam::950174689815:role/efs-on-demand; then
    echo "Failed to authenticate with AWS. Exiting."
    exit 1
fi

# Get user email from environment variable
USER_EMAIL="${GITPOD_GIT_USER_EMAIL}"

if [ -z "$USER_EMAIL" ]; then
    echo "User email not found. Make sure GITPOD_GIT_USER_EMAIL is set. Exiting."
    exit 1
fi

# Check if EFS volume exists
VOLUME_NAME="${USER_EMAIL//@/-at-}"
VOLUME_ID=$(aws efs describe-file-systems --query "FileSystems[?Name=='$VOLUME_NAME'].FileSystemId" --output text)

if [ -z "$VOLUME_ID" ]; then
    echo "Creating new EFS volume for $USER_EMAIL"
    VOLUME_ID=$(aws efs create-file-system --creation-token "$VOLUME_NAME" --tags Key=Name,Value="$VOLUME_NAME" --query "FileSystemId" --output text)
    echo "Created EFS volume with ID: $VOLUME_ID"
else
    echo "EFS volume for $USER_EMAIL already exists with ID: $VOLUME_ID"
fi

# Install EFS utils if not already installed
if ! command -v mount.efs &> /dev/null; then
    echo "Installing EFS utils..."
    sudo apt-get update
    sudo apt-get install -y amazon-efs-utils
fi

# Create mount directory
sudo mkdir -p /workspace/efs

# Mount EFS volume
echo "Mounting EFS volume to /workspace/efs..."
sudo mount -t efs -o tls $VOLUME_ID:/ /workspace/efs

# Add entry to /etc/fstab for persistent mount
echo "$VOLUME_ID:/ /workspace/efs efs _netdev,tls,iam 0 0" | sudo tee -a /etc/fstab

echo "EFS volume mounted successfully at /workspace/efs"