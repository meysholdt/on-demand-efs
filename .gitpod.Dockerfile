FROM gitpod/workspace-full

USER root

RUN sudo apt-get update && \
    sudo apt-get install -y awscli jq  && \
    pip install boto3

USER gitpod