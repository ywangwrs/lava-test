#!/bin/bash

# variables among functions
S3_BUCKET='s3://s3-build-images'
requesting_images_folder=''
local_images_base_folder=/home/ywang/awsbuilds
local_images_http_link=http://yow-lpdtest.wrs.com/tftpboot/awsbuilds

LAVA_JOB_SUBMIT_SCRIPT=./launch_lava_test.sh
images_access_remote_base=/net/yow-lpdtest/var/lib/tftpboot/awsbuilds
LAVA_USER=lpdtest
LAVA_SERVER=yow-lab-simics16.wrs.com:8080
TEST_SUITE=linaro-smoke-test
TEST_DEVICE=x86
RETRY=0
EMAIL=yang.wang@windriver.com

currsec=$(date +%s)
teststat_file=/tmp/teststats_${currsec}.json
ELASTICSEARCH_SERVER=""

function get_es_server_public_ip() {
    local info=$(./get_ec2_instances_info.sh | grep "ElasticSearchServer")
    local array=($info)
    ELASTICSEARCH_SERVER="${array[4]}"
    
    if [ -z "$ELASTICSEARCH_SERVER" ]; then
        echo "Can't find running ElasticSearch server in AWS!"
    else
        echo "ElasticSearch Searver IP = $ELASTICSEARCH_SERVER"
    fi
}

function mark_done_in_s3() {
    echo "Replace runtime-test-in-progress with runtime-test-done in S3 ..."
    aws s3 mv ${S3_BUCKET}/${requesting_images_folder}/runtime-test-in-progress ${S3_BUCKET}/${requesting_images_folder}/runtime-test-done
    aws s3 ls --recursive ${S3_BUCKET}/${requesting_images_folder}
    mv ${local_images_base_folder}/${requesting_images_folder}/runtime-test-in-progress ${local_images_base_folder}/${requesting_images_folder}/runtime-test-done
    echo "Done!"
}

function mark_done_locally() {
    echo "Replace need-runtime-test with runtime-test-done locally ..."
    mv ${local_images_base_folder}/${requesting_images_folder}/need-runtime-test ${local_images_base_folder}/${requesting_images_folder}/runtime-test-done
    echo "Done!"
}

function report() {
    local remote_report_file=/tmp/${requesting_images_folder}_teststats.json
    echo "==="
    echo "Report to ElasticSearch server ..."

    scp -i wrigel-server.pem  -o "StrictHostKeyChecking no" "$teststat_file" ubuntu@${ELASTICSEARCH_SERVER}:${remote_report_file}
    local report_cmd="curl -XPOST http://localhost:9200/wrigel-$(date "+%Y.%m.%d")/logs -H 'Content-Type: application/json' -d @$remote_report_file"

    ssh -i wrigel-server.pem  -o "StrictHostKeyChecking no" ubuntu@${ELASTICSEARCH_SERVER} "$report_cmd"
    echo "Done!"
}

function submit_lava_job() {
    teststat_file=${local_images_base_folder}/${requesting_images_folder}/teststats.json
    local test_export_image=''
    local rpm_pkg=''

    echo "==="
    echo "Start LAVA test ..."
    
    TEST_SUITE=$(cat $teststat_file | jq .'test_info.test_suite')
    TEST_SUITE=$(echo $TEST_SUITE | tr -d '"')
    echo "Test suite: $TEST_SUITE"

    if [ "$TEST_SUITE" == 'oeqa-default-test' ]; then
        test_export_image=${local_images_http_link}/${requesting_images_folder}/testexport.tar.gz

	rpm_pkg_name=`find ${local_images_base_folder}/${requesting_images_folder} -name *.rpm -exec basename {} \;`
        rpm_pkg=${local_images_http_link}/${requesting_images_folder}/${rpm_pkg_name}
    fi

    echo "$LAVA_JOB_SUBMIT_SCRIPT -o $teststat_file \ "
    echo "-b ${local_images_base_folder}/${requesting_images_folder} \ "
    echo "-n ${local_images_http_link} \ "
    echo "-s ${TEST_SUITE} \ "
    echo "-k ${images_access_remote_base}/${requesting_images_folder}/bzImage \ "
    echo "-r ${images_access_remote_base}/${requesting_images_folder}/wrlinux-image-glibc-std-genericx86-64.tar.bz2 \ "
    echo "-p ${test_export_image} \ "
    echo "-m ${rpm_pkg} \ "
    echo "-d $TEST_DEVICE \ "
    echo "-e $EMAIL"

    $LAVA_JOB_SUBMIT_SCRIPT -o $teststat_file \
    -b "${local_images_base_folder}/${requesting_images_folder}" \
    -n "${local_images_http_link}/${requesting_images_folder}" \
    -s "${TEST_SUITE}" \
    -k "${images_access_remote_base}/${requesting_images_folder}/bzImage" \
    -r "${images_access_remote_base}/${requesting_images_folder}/wrlinux-image-glibc-std-genericx86-64.tar.bz2" \
    -p "${test_export_image}" \
    -m "${rpm_pkg}" \
    -d "$TEST_DEVICE" \
    -e "$EMAIL"

    echo "Done!"

    report
}

function download_s3_images() {
    echo "==="
    echo "Replace need-runtime-test with runtime-test-in-progress in S3 ..."
    aws s3 mv ${S3_BUCKET}/${requesting_images_folder}/need-runtime-test ${S3_BUCKET}/${requesting_images_folder}/runtime-test-in-progress
    aws s3 ls --recursive ${S3_BUCKET}/${requesting_images_folder}
    echo "Done!"

    echo "Downloading images from ${S3_BUCKET}/${requesting_images_folder} ..."
    mkdir "${local_images_base_folder}/${requesting_images_folder}"
    aws s3 cp --recursive ${S3_BUCKET}/${requesting_images_folder} ${local_images_base_folder}/${requesting_images_folder}/
    ls -la ${local_images_base_folder}/${requesting_images_folder}
    echo "Done!"

    submit_lava_job
}

function check_s3_quests() {
    # aws s3 ls --recursive s3://s3-build-images
    local REQUESTS=/tmp/s3_requests_${currsec}

    aws s3 ls --recursive "$S3_BUCKET" | grep need-runtime-test > "$REQUESTS"

    if [ "$?" == 0 ]; then
	local request_line=$(head -n 1 $REQUESTS)
	local array=(${request_line// / })
	requesting_images_folder=$(echo ${array[3]} | sed 's/\/need-runtime-test//g')
	echo "Requesting runtime test from: ${requesting_images_folder}"
        download_s3_images
	mark_done_in_s3
    else
	requesting_images_folder=''
        echo "No test request from S3!"
    fi
}

function check_local_requests() {
    local REQUESTS=/tmp/local_requests_${currsec}

    find "$local_images_base_folder" -name need-runtime-test > "$REQUESTS"

    if [ -s "$REQUESTS" ]; then
	local request_line=$(head -n 1 $REQUESTS)
	request_line=$(echo "$request_line" | sed 's/\/need-runtime-test//g')
	requesting_images_folder=$(basename "$request_line")
	echo "Requesting runtime test from: ${requesting_images_folder}"
        submit_lava_job
	mark_done_locally
    else
	requesting_images_folder=''
        echo "No test request from $local_images_base_folder!"
    fi
}

function check_lava_job_status() {
    echo "."
}

function show_sleep_progress() {
    local loop=$1
    local sleep_time=$2

    for ((j=$sleep_time;j>=0;j--))
    do
	sleep 1
	echo -ne "Wait loop No.$loop: $j \r"
    done
}

function main_for_s3() {
    get_es_server_public_ip

    while true; do
	echo "$(date +'%Y-%m-%d %H:%M'):"
        check_s3_quests
	show_sleep_progress 1 60
    done
}
function main() {
    get_es_server_public_ip

    while true; do
	echo "$(date +'%Y-%m-%d %H:%M'):"
        check_local_requests
	show_sleep_progress 1 60
    done
}

main "$@"
