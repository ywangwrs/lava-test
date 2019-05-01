#!/bin/bash

sed -i '/"DEPLOY_DIR"/c\        "DEPLOY_DIR": "/root",' testdata.json 
sed -i '/"DEPLOY_DIR_IMAGE"/c\        "DEPLOY_DIR_IMAGE": "/root",' testdata.json 
sed -i '/"DEPLOY_DIR_RPM"/c\        "DEPLOY_DIR_RPM": "/root",' testdata.json 
sed -i '/"ip"/c\        "ip": "localhost",' testdata.json
sed -i '/"TEST_TARGET_IP"/c\        "TEST_TARGET_IP": "localhost",' testdata.json
