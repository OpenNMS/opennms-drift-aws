#!/bin/bash

region=${1-us-east-2};
source_ami=${2-ami-0d8f6eb4f641ef691};

echo "AWS Region: $region"
echo "AWS Source AMI: $source_ami"
echo

if hash packer 2>/dev/null; then
  packer build -var "region=$region" -var "source_ami=$source_ami" cassandra.json  && \
  packer build -var "region=$region" -var "source_ami=$source_ami" elasticsearch.json && \
  packer build -var "region=$region" -var "source_ami=$source_ami" kafka.json  && \
  packer build -var "region=$region" -var "source_ami=$source_ami" kibana.json && \
  packer build -var "region=$region" -var "source_ami=$source_ami" opennms.json  && \
  packer build -var "region=$region" -var "source_ami=$source_ami" sentinel.json  && \
  packer build -var "region=$region" -var "source_ami=$source_ami" postgresql.json
else
  echo "ERROR: Packer is not installed."
  echo "       Please go to https://packer.io/ and follow the instructions."
fi
