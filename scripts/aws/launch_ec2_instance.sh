#!/bin/bash

usage() {
  cat << EOF >&2
Usage: $0 [-t <type>] [-a <ami>]

  -t <AWS EC2 instance type>: instance type, such as c5.xlarge (default), c5.2xlarge ...
-a <AWS EC2 AMI information>: without_sstate (default), with_sstate, AMI_ID
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
    AMI_ID="ami-0ebe9c5f15d851ddf"   # without sstate
elif [[ "$instance_ami" == 'with_sstate' ]]; then
    AMI_ID="ami-0a93b3c96fc3ff1ad"   # with sstate
elif [[ "$instance_ami" == 'without_sstate' ]]; then
    AMI_ID="ami-0ebe9c5f15d851ddf"   # without sstate
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
