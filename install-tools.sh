#!/bin/bash
apt update
apt install -y  jq \
                curl \
                git \
                unzip \
                vim
cd /tmp
curl -fsSL -o /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 /tmp/get_helm.sh
/tmp/get_helm.sh

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
mv ./kubectl /usr/local/bin/kubectl
chmod +x /usr/local/bin/kubectl

curl "https://awscli.amazonaws.com/awscli-exe-linux-amd64.zip" -o "awscliv2.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update

sh -c "$(curl -sSfL https://release.solana.com/v1.16.13/install)"
