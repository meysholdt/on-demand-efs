#!/bin/bash

set -e

# Get user email from environment variable
USER_EMAIL="${GITPOD_GIT_USER_EMAIL}"

if [ -z "$USER_EMAIL" ]; then
    echo "User email not found. Make sure GITPOD_GIT_USER_EMAIL is set. Exiting."
    exit 1
fi

# Subnet IDs
SUBNET_IDS=("subnet-0371e153d84b71cb4" "subnet-0d9d31906e208983f" "subnet-067196425e7fb51d6")

# Security Group ID
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
        STATE=$(aws efs describe-file-systems --file-system-id $VOLUME_ID --query "FileSystems[0].LifeCycleState" --output text)
        if [ "$STATE" = "available" ]; then
            echo "EFS volume is now available."
            break
        fi
        echo "EFS volume state: $STATE. Waiting..."
        sleep 10
    done

    # Create mount targets for each subnet
    for SUBNET_ID in "${SUBNET_IDS[@]}"; do
        echo "Creating mount target for EFS volume $VOLUME_ID in subnet $SUBNET_ID"
        MOUNT_TARGET_ID=$(aws efs create-mount-target --file-system-id $VOLUME_ID --subnet-id $SUBNET_ID --security-groups $SECURITY_GROUP_ID --query "MountTargetId" --output text)
        echo "Created mount target with ID: $MOUNT_TARGET_ID"
    done

    # Wait for all mount targets to become available
    echo "Waiting for all mount targets to become available..."
    while true; do
        ALL_AVAILABLE=true
        for SUBNET_ID in "${SUBNET_IDS[@]}"; do
            STATE=$(aws efs describe-mount-targets --file-system-id $VOLUME_ID --query "MountTargets[?SubnetId=='$SUBNET_ID'].LifeCycleState" --output text)
            if [ "$STATE" != "available" ]; then
                ALL_AVAILABLE=false
                echo "Mount target in subnet $SUBNET_ID state: $STATE. Waiting..."
                break
            fi
        done
        if $ALL_AVAILABLE; then
            echo "All mount targets are now available."
            break
        fi
        sleep 10
    done
else
    echo "EFS volume for $USER_EMAIL already exists with ID: $VOLUME_ID"
fi

# Get the EFS DNS name
export EFS_DNS_NAME="${VOLUME_ID}.efs.eu-central-1.amazonaws.com"
