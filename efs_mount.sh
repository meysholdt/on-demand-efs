#!/bin/bash
# .gitpod/setup_efs.sh

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

# Specific subnet ID
SUBNET_ID="subnet-0371e153d84b71cb4"

# Security group ID
SECURITY_GROUP_ID="sg-030b31eb62d8bb81f"

# Check if EFS volume exists
VOLUME_NAME="${USER_EMAIL//@/-at-}"
VOLUME_ID=$(aws efs describe-file-systems --query "FileSystems[?Name=='$VOLUME_NAME'].FileSystemId" --output text)

if [ -z "$VOLUME_ID" ]; then
    echo "Creating new EFS volume for $USER_EMAIL"
    VOLUME_ID=$(aws efs create-file-system --creation-token "$VOLUME_NAME" --tags Key=Name,Value="$VOLUME_NAME" --query "FileSystemId" --output text)
    echo "Created EFS volume with ID: $VOLUME_ID"
    
    echo "Waiting for EFS volume to become available..."
    while true; do
        STATUS=$(aws efs describe-file-systems --file-system-id $VOLUME_ID --query "FileSystems[0].LifeCycleState" --output text)
        if [ "$STATUS" = "available" ]; then
            echo "EFS volume is now available."
            break
        fi
        echo "EFS volume status: $STATUS. Waiting..."
        sleep 10
    done
else
    echo "EFS volume for $USER_EMAIL already exists with ID: $VOLUME_ID"
fi

# Check if mount target exists
MOUNT_TARGET_ID=$(aws efs describe-mount-targets --file-system-id $VOLUME_ID --query "MountTargets[?SubnetId=='$SUBNET_ID'].MountTargetId" --output text)

if [ -z "$MOUNT_TARGET_ID" ]; then
    echo "Creating mount target for EFS volume $VOLUME_ID in subnet $SUBNET_ID"
    MOUNT_TARGET_ID=$(aws efs create-mount-target --file-system-id $VOLUME_ID --subnet-id $SUBNET_ID --security-groups $SECURITY_GROUP_ID --query "MountTargetId" --output text)
    echo "Created mount target with ID: $MOUNT_TARGET_ID"
    
    echo "Waiting for mount target to become available..."
    while true; do
        STATUS=$(aws efs describe-mount-targets --mount-target-id $MOUNT_TARGET_ID --query "MountTargets[0].LifeCycleState" --output text)
        if [ "$STATUS" = "available" ]; then
            echo "Mount target is now available."
            break
        fi
        echo "Mount target status: $STATUS. Waiting..."
        sleep 10
    done
else
    echo "Mount target already exists with ID: $MOUNT_TARGET_ID"
fi

# Get the EFS DNS name
EFS_DNS_NAME="${VOLUME_ID}.efs.eu-central-1.amazonaws.com"

# Create mount directory
sudo mkdir -p /workspace/efs

# Mount EFS volume using NFS client
echo "Mounting EFS volume to /workspace/efs..."
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${EFS_DNS_NAME}:/ /workspace/efs

# Add entry to /etc/fstab for persistent mount
echo "${EFS_DNS_NAME}:/ /workspace/efs nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport,_netdev 0 0" | sudo tee -a /etc/fstab

echo "EFS volume mounted successfully at /workspace/efs"