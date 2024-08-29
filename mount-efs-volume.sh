#!/bin/bash

set -e

# load EFS_DNS_NAME env var
source .env

# Create mount directory
sudo mkdir -p /workspace/efs

# Mount EFS volume using NFS client
echo "Mounting EFS volume to /workspace/efs..."
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${EFS_DNS_NAME}:/ /workspace/efs

echo "EFS volume mounted successfully at /workspace/efs"