#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

######### CUSTOMIZED VARIABLES #########

onms_repo="stable"
onms_version="-latest-"
grafana_version="6.6.1"

########################################

opennms_home=/opt/opennms
opennms_etc=$opennms_home/etc

echo "### Installing Common Packages..."

sudo yum -y -q install haveged redis httpd
sudo systemctl enable haveged

echo "### Installing Grafana $grafana_version..."

sudo yum install -y -q https://dl.grafana.com/oss/release/grafana-$grafana_version-1.x86_64.rpm 

echo "### Installing OpenNMS Dependencies from stable repository..."

sudo sed -r -i '/name=Amazon Linux 2/a exclude=rrdtool-*' /etc/yum.repos.d/amzn2-core.repo
sudo yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-stable-rhel7.noarch.rpm
sudo rpm --import /etc/yum.repos.d/opennms-repo-stable-rhel7.gpg
sudo yum install -y -q jicmp jicmp6 jrrd jrrd2 rrdtool 'perl(LWP)' 'perl(XML::Twig)'

echo "### Installing OpenNMS..."

if [ "$onms_repo" != "stable" ]; then
  echo "### Installing OpenNMS $onms_repo Repository..."
  sudo yum remove -y -q opennms-repo-stable
  sudo yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-$onms_repo-rhel7.noarch.rpm
  sudo rpm --import /etc/yum.repos.d/opennms-repo-$onms_repo-rhel7.gpg
fi

suffix=""
if [ "$onms_version" == "-latest-" ]; then
  echo "### Installing latest OpenNMS from $onms_repo Repository..."
else
  echo "### Installing OpenNMS version $onms_version from $onms_repo Repository..."
  suffix="-$onms_version"
fi
sudo yum install -y -q opennms-core$suffix opennms-webapp-jetty$suffix opennms-webapp-hawtio$suffix
sudo yum install -y -q opennms-helm
sudo yum clean all

echo "### Initializing GIT at $opennms_etc..."

cd $opennms_etc
sudo git init .
sudo git add .
sudo git commit -m "OpenNMS Installed."
cd

echo "### Copying external configuration files..."

src_dir=/tmp/sources
sudo chown -R root:root $src_dir/
sudo rsync -avr $src_dir/ /opt/opennms/etc/

echo "### Apply common configuration changes..."

sudo sed -r -i 's/value="DEBUG"/value="WARN"/' $opennms_etc/log4j2.xml
sudo sed -r -i '/manager/s/WARN/DEBUG/' $opennms_etc/log4j2.xml

sudo chown -R root:root $opennms_etc/

echo "### Enabling CORS..."

webxml=$opennms_home/jetty-webapps/opennms/WEB-INF/web.xml
sudo cp $webxml $webxml.bak
sudo sed -r -i '/[<][!]--/{$!{N;s/[<][!]--\n  ([<]filter-mapping)/\1/}}' $webxml
sudo sed -r -i '/nrt/{$!{N;N;s/(nrt.*\n  [<]\/filter-mapping[>])\n  --[>]/\1/}}' $webxml
