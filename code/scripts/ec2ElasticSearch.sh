#!/bin/bash
sudo su
set -x
sudo apt-get update -y
sudo apt-get install -y git ec2-instance-connect

until git clone https://github.com/aws-quickstart/quickstart-linux-utilities.git; do echo "Retrying"; done
cd /quickstart-linux-utilities
source quickstart-cfn-tools.source
qs_update-os || qs_err
qs_bootstrap_pip || qs_err
qs_aws-cfn-bootstrap || qs_err
mkdir -p /opt/aws/bin
ln -s /usr/local/bin/cfn-* /opt/aws/bin/

curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elastic.gpg
echo "deb [signed-by=/usr/share/keyrings/elastic.gpg] https://artifacts.elastic.co/packages/7.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-7.x.list
sudo apt update
sudo apt install elasticsearch
sudo sh -c "echo '
cluster.name: leadHawk
discovery.seed_providers: ec2
discovery.ec2.host_type: private_ip  # or 'public_ip' based on your setup
discovery.ec2.tag.Role: "elasticsearch"  # Replace with your actual EC2 tag
cluster.initial_master_nodes:
- node-1
- node-2
node.name: node-2
network.host: _ec2_
node.master: true' >> /etc/elasticsearch/elasticsearch.yml"
sudo systemctl start elasticsearch
sudo systemctl enable elasticsearch
echo "y" | sudo /usr/share/elasticsearch/bin/elasticsearch-plugin install repository-s3
echo "y" | sudo /usr/share/elasticsearch/bin/elasticsearch-plugin install discovery-ec2
sudo systemctl restart elasticsearch