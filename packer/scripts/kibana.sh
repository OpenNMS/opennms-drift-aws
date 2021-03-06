#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

######### CUSTOMIZED VARIABLES #########

es_version="7.3.0"

########################################

kibana_config=/etc/kibana

echo "### Downloading and installing Kibana version $es_version..."

sudo yum install -y -q https://artifacts.elastic.co/downloads/kibana/kibana-$es_version-x86_64.rpm

echo "### Initializing GIT at $kibana_config..."

sudo cd $kibana_config
sudo git init .
sudo git add .
sudo git commit -m "Kibana $es_version installed."
cd
