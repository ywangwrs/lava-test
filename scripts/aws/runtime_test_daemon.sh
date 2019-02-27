#!/bin/bash

# variables among functions
S3_BUCKET='s3://s3-build-images'
requesting_images_folder=''
local_images_base_folder=/home/ywang/awsbuilds

function submit_lava_job() {
    echo "."
}

function download_s3_images() {
    echo "==="
    echo "Downloading images from ${S3_BUCKET}/${requesting_images_folder} ..."
    mkdir "${local_images_base_folder}/${requesting_images_folder}"
    aws s3 cp --recursive ${S3_BUCKET}/${requesting_images_folder} ${local_images_base_folder}/${requesting_images_folder}/
    ls -la ${local_images_base_folder}/${requesting_images_folder}
    echo "Done!"
}

function check_s3_quests() {
    # aws s3 ls --recursive s3://s3-build-images
    local REQUESTS=/tmp/s3_requests

    aws s3 ls --recursive "$S3_BUCKET" | grep need-runtime-test > "$REQUESTS"

    if [ "$?" == 0 ]; then
	local request_line=$(head -n 1 $REQUESTS)
	local array=(${request_line// / })
	requesting_images_folder=$(echo ${array[3]} | sed 's/\/need-runtime-test//g')
	echo "Requesting runtime test from: ${requesting_images_folder}"
        download_s3_images
    else
	requesting_images_folder=''
        echo "No S3 Request!"
    fi
}

function check_lava_job_status() {
    echo "."
}

function report() {
    echo "."
}

function main() {
    check_s3_quests
}

main "$@"
