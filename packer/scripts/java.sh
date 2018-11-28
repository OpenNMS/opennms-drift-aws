#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
#
# Set the USE_LATEST_JAVA environment variable in order to use latest Java instead of Java 8

echo "### Downloading and installing latest Oracle JDK..."

java_url="https://download.oracle.com/otn-pub/java/jdk/8u191-b12/2787e4a523244c269598db4e85c51e0c/jdk-8u191-linux-x64.rpm"
if [ "$USE_LATEST_JAVA" != "" ]; then
  java_url="https://download.oracle.com/otn-pub/java/jdk/11.0.1+13/90cf5d8f270a4347a95050320eef3fb7/jdk-11.0.1_linux-x64_bin.rpm"
fi

java_rpm=/tmp/oracle-jdk-linux-x64.rpm

wget -c --quiet --header "Cookie: oraclelicense=accept-securebackup-cookie" -O $java_rpm $java_url

if [ ! -s $java_rpm ]; then
  echo "### FATAL: Cannot download Java from $java_url. Using the JDK available at OpenNMS stable repository ..."
  sudo yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-stable-rhel7.noarch.rpm
  sudo rpm --import /etc/yum.repos.d/opennms-repo-stable-rhel7.gpg
  sudo yum install -y -q jdk1.8*
  sudo yum erase -y -q opennms-repo-stable
else
  echo "### Installing Java from $java_url..."
  sudo yum install -y -q $java_rpm
  sudo rm -f $java_rpm
fi
