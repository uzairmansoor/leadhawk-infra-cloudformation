#!/bin/bash
set -x
apt-get update -y
apt-get install -y git ec2-instance-connect unzip ca-certificates curl
install -m 0755 -d /etc/apt/keyrings

# Add Docker's GPG key and Docker repository
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update and install Docker
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Clone AWS QuickStart Linux utilities
until git clone https://github.com/aws-quickstart/quickstart-linux-utilities.git;
do echo "Retrying"; done

cd /quickstart-linux-utilities
source quickstart-cfn-tools.source
qs_update-os || qs_err
qs_bootstrap_pip || qs_err
qs_aws-cfn-bootstrap || qs_err

# Setup AWS CloudFormation tools
mkdir -p /opt/aws/bin
ln -s /usr/local/bin/cfn-* /opt/aws/bin/

# Install Apache and enable necessary modules
apt update
apt install apache2 -y
a2enmod proxy proxy_http proxy_balancer lbmethod_byrequests

# Add 'ubuntu' user to Docker group
usermod -a -G docker ubuntu

# Enable and start Docker and Apache services
systemctl enable docker
systemctl start docker
systemctl restart apache2
systemctl restart docker

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install
rm awscliv2.zip

# Set environment variables for ECR and repositories
export ECR_URL=627414718330.dkr.ecr.us-east-2.amazonaws.com
export Region=us-east-1
export SCRAPPER_REPO_NAME=scrapingservice
export DATA_EXTRACTOR_REPO_NAME=dataextractorservice

# Run CloudFormation Init and Signal
(
    set +e
    /opt/aws/bin/cfn-init -v --region 
- Ref: AWS::Region
- " --stack "
- Ref: AWS::StackName
- " --resource LeadHawkScrapperEC2051B7890 -c default

    /opt/aws/bin/cfn-signal -e $? --region "
- Ref: AWS::Region
- " --stack "
- Ref: AWS::StackName
- |
    --resource LeadHawkScrapperEC2051B7890
    cat /var/log/cfn-init.log >&2
)