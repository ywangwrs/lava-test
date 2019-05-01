#!/bin/bash

usage() {
  cat << EOF >&2
Usage: $0 [-t <type>] [-a <ami>]

-t <AWS EC2 instance type>: instance type, such as c5.xlarge (default), c5.2xlarge ...
       -a <AWS EC2 AMI ID>: AMI_ID or empty to use the default AMI
EOF
  exit 1
}

while getopts "t:a:" opt; do
  case $opt in
    t) instance_type=$OPTARG
       ;;
    a) instance_ami=$OPTARG
       ;;
    h) usage
       ;;
    *) usage
       ;;
  esac
done
shift "$((OPTIND - 1))"

if [ -z "$instance_type" ]; then
    instance_type=c5.xlarge
fi

if [ -z "$instance_ami" ]; then
    AMI_ID="ami-0b403931f5e8e0cad"   # wrigel-lava.docker.2019.03 wrlinux 10.18 base
else
    AMI_ID="$instance_ami"           # given AMI ID
fi

SECURITY_GROUP_IDS="sg-00d2e987555ec2ab5"
SECURITY_KEY_NAME="wrigel-server"
IAM_ROLE=EC2IAMRole

aws ec2 run-instances \
	--image-id "$AMI_ID" \
	--count 1 \
	--instance-type "$instance_type" \
	--security-group-ids "$SECURITY_GROUP_IDS" \
	--key-name "$SECURITY_KEY_NAME" \
	--iam-instance-profile Name="$IAM_ROLE" \
	--tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=wrigel-lava-instance}]' \
	--query 'Instances[0].InstanceId' --output text
