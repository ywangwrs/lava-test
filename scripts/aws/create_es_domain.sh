#!/bin/bash

DOMAIN_NAME=wrigel-report
ES_VERSION=6.4
ES_INSTANCE_TYPE=t2.medium.elasticsearch
ES_INSTANCE_NUMBER=2
ES_INSTANCE_VOLUME_TYPE=gp2
ES_INSTANCE_VOLUME_SIZE=10
VPC=vpc-0a975e72
VPC_SUBNET=subnet-f46125bf    #172.31.32.0/20|us-west-2b
VPC_SECURITY_GROUP=sg-00d2e987555ec2ab5
ACCESS_POLICY='{"Version": "2012-10-17", "Statement": [ { "Effect": "Allow", "Principal": {"AWS": "*" }, "Action":"es:*", "Resource": "arn:aws:es:us-west-2:464224200125:domain/wrigel-report/*" } ] }'

function show_sleep_progress() {
    local loop=$1
    local sleep_time=$2

    for ((j=$sleep_time;j>=0;j--))
    do
	sleep 1
	echo -ne "Wait loop No.$loop: $j \r"
    done
}

function get_elasticsearch_url () {
    elasticsearch_url=$(aws es describe-elasticsearch-domain --domain-name wrigel-report --output json | grep 'vpc":' | tr -d '\n[] "' | sed 's/vpc://g')

    echo "$elasticsearch_url"
}

while true;
do
    es_status=$(aws es describe-elasticsearch-domain --domain-name wrigel-report --output json | grep '"Processing":' | tr -d '\n[] "' | sed 's/,//g' | sed 's/ //g' | sed 's/Processing://g')
    echo $es_status
    if [[ "$es_status" == 'ture' ]]; then
        show_sleep_progress 1 20
    else
        break
    fi
done 

#aws es create-elasticsearch-domain \
#--domain-name "$DOMAIN_NAME" \
#--elasticsearch-version "$ES_VERSION" \
#--elasticsearch-cluster-config InstanceType="$ES_INSTANCE_TYPE",InstanceCount="$ES_INSTANCE_NUMBER" \
#--ebs-options EBSEnabled=true,VolumeType="$ES_INSTANCE_VOLUME_TYPE",VolumeSize="$ES_INSTANCE_VOLUME_SIZE" \
#--access-policies "$ACCESS_POLICY" \
#--vpc-options SubnetIds="$VPC_SUBNET",SecurityGroupIds="$VPC_SECURITY_GROUP"
