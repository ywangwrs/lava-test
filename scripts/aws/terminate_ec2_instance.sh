#!/bin/bash

if [ -z $1 ]; then
    echo "Usage: $0 <instance_id>"
    exit
fi

instance_id=$1

echo "Terminating instance $instance_id ..."
aws ec2 terminate-instances --instance-ids "$instance_id" &> /dev/null
echo "Done"

