#!/bin/bash
if [ -z $1 ]; then
    cd /opt/ci-scripts
    ./start_jenkins.sh --no-pull
elif [ "$1" == 'shutdown' ]; then
    cd /opt/ci-scripts
    ./start_jenkins.sh --shutdown
fi
