#!/bin/bash
sudo su
set -x
sudo apt-get update -y
sudo apt-get install -y git ec2-instance-connect unzip
sudo apt-get install -y ca-certificates curl

# Install Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Clone quickstart-linux-utilities and perform necessary configurations
until git clone https://github.com/aws-quickstart/quickstart-linux-utilities.git; do echo "Retrying"; done
cd /quickstart-linux-utilities
source quickstart-cfn-tools.source
qs_update-os || qs_err
qs_bootstrap_pip || qs_err
qs_aws-cfn-bootstrap || qs_err
mkdir -p /opt/aws/bin
ln -s /usr/local/bin/cfn-* /opt/aws/bin/

# Install Apache and configure virtual hosts
apt update
apt install apache2 -y
a2enmod proxy proxy_http proxy_balancer lbmethod_byrequests

export ECR_URL=627414718330.dkr.ecr.us-east-2.amazonaws.com
export Region=us-east-1
export ADMINSERVICE=adminservice
export DATASERVICE=dataservice
export FILTERSERVICE=filterservice
export USERSERVICE=userservice
export ADMINDOMAIN=adminservice.leadhawk.io
export DATADOMAIN=dataservice.leadhawk.io
export FILTERDOMAIN=filterservice.leadhawk.io
export USERDOMAIN=userservice.leadhawk.io

# Apache VirtualHost configuration
echo "
<VirtualHost *:80>
ServerName $ADMINDOMAIN
ProxyPass / http://localhost:6005/
ProxyPassReverse / http://localhost:6005/
</VirtualHost>

<VirtualHost *:80>
ServerName $DATADOMAIN
ProxyPass / http://localhost:6003/
ProxyPassReverse / http://localhost:6003/
</VirtualHost>

<VirtualHost *:80>
ServerName $USERDOMAIN
ProxyPass / http://localhost:6001/
ProxyPassReverse / http://localhost:6001/
</VirtualHost>

<VirtualHost *:80>
ServerName $FILTERDOMAIN
ProxyPass / http://localhost:6004/
ProxyPassReverse / http://localhost:6004/
</VirtualHost>
" >> /etc/apache2/sites-available/000-default.conf

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install
rm awscliv2.zip

# Docker Compose configuration
sudo systemctl enable docker
sudo systemctl start docker
sudo systemctl restart apache2
sudo systemctl restart docker

# Create Docker Compose YAML file
sudo sh -c "cat > /home/ubuntu/compose.yml <<EOL
name: compose-leadhawk-ec2

services:
  admin-service:
    container_name: leadhawk_admin
    image: $ECR_URL/$ADMINSERVICE:latest
    pull_policy: always
    restart: on-failure:3
    logging:
      driver: awslogs
      options:
        awslogs-group: leadhawk_admin
        awslogs-region: $Region
    ports:
      - 6005:6005

  dataentry-service:
    container_name: leadhawk_dataentry
    image: $ECR_URL/$DATASERVICE:latest
    pull_policy: always
    restart: on-failure:3
    logging:
      driver: awslogs
      options:
        awslogs-group: leadhawk_dataentry
        awslogs-region: $Region
    ports:
      - 6003:6003

  filter-service:
    container_name: leadhawk_filter
    image: $ECR_URL/$FILTERSERVICE:latest
    pull_policy: always
    restart: on-failure:3
    logging:
      driver: awslogs
      options:
        awslogs-group: leadhawk_filter
        awslogs-region: $Region
    ports:
      - 6004:6004

  user-service:
    container_name: leadhawk_user
    image: $ECR_URL/$USERSERVICE:latest
    pull_policy: always
    restart: on-failure:3
    logging:
      driver: awslogs
      options:
        awslogs-group: leadhawk_user
        awslogs-region: $Region
    ports:
      - 6001:6001
EOL"

# Run services
ECR_REGION=$(echo $ECR_URL | awk -F '.' '{print $4}')
aws ecr get-login-password --region $ECR_REGION | sudo docker login --username AWS --password-stdin $ECR_URL
sudo docker compose -f /home/ubuntu/compose.yml up --build -d