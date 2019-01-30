#!/bin/bash
# Wait until postgresql start
sleep 15

# Set LAVA Server IP
if [[ -n "$LAVA_SERVER_IP" ]]; then
    sed -i "s/.*LAVA_SERVER_IP =.*/LAVA_SERVER_IP = $LAVA_SERVER_IP/g" /etc/lava-dispatcher/lava-dispatcher.conf
fi

# Check if lpdtest has been registered
LAVA_API_TOKEN=$(lava-server manage tokens list --user lpdtest --csv | awk -F "\"*,\"*" '{if (NR==2) {print $2}}')

if [[ -n "$LAVA_API_TOKEN" ]]; then
    lava-tool auth-add http://lpdtest:${LAVA_API_TOKEN}@localhost
else
    # Create the admin user
    echo "from django.contrib.auth.models import User; User.objects.create_superuser('lpdtest', 'admin@localhost.com', 'lpdtest')" | lava-server manage shell

    # Set the lpdtest user's API token
    LAVA_API_TOKEN=`lava-server manage tokens add --user lpdtest`
    lava-tool auth-add http://lpdtest:${LAVA_API_TOKEN}@localhost
    
    # By default add a worker on the master
    lava-server manage workers add dispatcher01
    
    # Add x86-64 QEMU devices
    lava-server manage device-types details aws-ec2_qemu-x86_64
    if [[ $? != 0 ]]; then
        lava-server manage device-types add aws-ec2_qemu-x86_64
        lava-server manage devices add  --device-type aws-ec2_qemu-x86_64 --worker dispatcher01 x86_64_aws-ec2_qemu01
    fi
fi
