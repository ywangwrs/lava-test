#!/bin/bash
usage() {
  cat << EOF >&2
Usage: $0 [-u <user>] [-l <lava-server>] [-a <auth>] [-s <suite>] [-b <folder>] [-n <weblink>] [-d <device>] [-p <test_pkg>] [-m <rpm_pkg>] [-i <hddimg>] [-k <kernel>] [-r <rootfs>] [-t <retry> ] [-e <email>]

-u <lava username>               : LAVA username, by default, it's lpdtest
-l <lava server address>         : LAVA server address, by default, it's yow-lpdtest.wrs.com:8080 
-a <lava server auth token>      : auth-token of username in LAVA
-b <local images base folder>    : /home/ywang/awsbuilds/20190228_2201-genericx86-64_wrlinux_image-glibc-std
-n <local images http link>      : http://x.x.x.x/awsbuilds/20190228_2201-genericx86-64_wrlinux_image-glibc-std
-s <test suite name>             : by default, it' linaro-smoke-test
-d <test device name>            : by default, it's hardware
-p <test package name>           : for example: /net/yow-lpdtest/testexport.tar.gz
-m <rpm test package name>       : for example: /net/yow-lpdtest/rpm-doc-4.14.2-r0.ppc7400.rpm
-i <.hdd image location>         : for example: /net/yow-lpdtest/wrlinux-image-glibc-std-genericx86-64.hdd
-k <kernel image location>       : for example: /net/yow-lpdtest/bzImage
-r <rootfs image location>       : for example: /net/yow-lpdtest/wrlinux-image-glibc-std-genericx86-64.tar.bz2
-t <retry times in runtime test> : by default, it's 0
-e <email to get notification>   : email addresss
-o <output json file>            : for example: teststats.json
EOF
  exit 1
}

while getopts "u:l:a:b:n:s:d:p:m:i:k:r:t:e:o:" opt; do
  case $opt in
    u) LAVA_USER=$OPTARG
       ;;
    l) LAVA_SERVER=$OPTARG
       ;;
    a) AUTH_TOKEN=$OPTARG
       ;;
    b) IMAGES_FOLDER=$OPTARG
       ;;
    n) IMAGES_LINK=$OPTARG
       ;;
    s) TEST_SUITE=$OPTARG
       ;;
    d) TEST_DEVICE=$OPTARG
       ;;
    p) TEST_EXPORT_IMAGE=$OPTARG
       ;;
    m) RPM_PKG=$OPTARG
       ;;
    i) HDD_IMG=$OPTARG
       ;;
    k) KERNEL_IMG=$OPTARG
       ;;
    r) ROOTFS=$OPTARG
       ;;
    t) RETRY=$OPTARG
       ;;
    e) EMAIL=$OPTARG
       ;;
    o) TEST_STATFILE=$OPTARG
       ;;
    h) usage
       ;;
    *) usage
       ;;
  esac
done
shift "$((OPTIND - 1))"

currsec=$(date +%s)

if [ -z "$LAVA_USER" ]; then
    LAVA_USER=lpdtest
fi

if [ -z "$LAVA_SERVER" ]; then
    LAVA_SERVER=yow-lab-simics16.wrs.com:8080
fi

if [ -z "$AUTH_TOKEN" ]; then
    AUTH_TOKEN=e6qko2fdal312f9zyai49y8sjtsz60gynn7mky3hw6daj9r4kc2c9f7ln6mwayghe4g3xfo0jiug0d0uk2g316aax3cbcaa8c5me50dykeimlkkmwdhnaap4ci6cpjz7
fi

if [ -z "$TEST_SUITE" ]; then
    TEST_SUITE=linaro-smoke-test
fi

if [ -z "$TEST_DEVICE" ]; then
    TEST_DEVICE=hardware
fi

if [ -z "$RETRY" ]; then
    RETRY=0
fi

if [ -z "$TEST_STATFILE" ]; then
    TEST_STATFILE=/tmp/teststats_${currsec}.json
fi

function insert_key_to_json() {
    local tmp_file=/tmp/tmp_report_${currsec}.json
    json_file=$1
    object=$2
    key=$3
    value=$4

    jq ".$object |= . + {\"$key\": \"$value\"}" $json_file > $tmp_file && cp -f $tmp_file $json_file
}

TEST_MAIL=/tmp/test-mail_${currsec}.txt
TEST_REPORT=/tmp/${TEST_SUITE}_${currsec}.csv
#echo "Test info:" > "$TEST_STATFILE"
#echo "==========" >> "$TEST_STATFILE"
#echo "Start: $(date) ($(date +%s))" >> "$TEST_STATFILE"

function generate_test_mail () {
    STATUS=$1
    SMTPSERVER=prod-webmail.windriver.com

    echo "Subject: [lava-webapp][$STATUS] Test $TEST_SUITE on $TEST_DEVICE finished" > $TEST_MAIL
    echo "" >> $TEST_MAIL
    cat $TEST_STATFILE >> $TEST_MAIL

    # Build up set of --to addresses as bash array because it properly passes
    # sets of args to another program
    local ADDRESS=
    set -f; IFS=,
    for ADDRESS in $EMAIL ; do
        TO_STR=("${TO_STR[@]}" --to "$ADDRESS")
    done
    set +f; unset IFS

    if [[ $EMAIL != 'disabled' ]]; then
        git config --global user.email "wrigel@windriver.com"
        git send-email --from=wrigel@windriver.com --quiet --confirm=never \
            "${TO_STR[@]}" "--smtp-server=$SMTPSERVER" "$TEST_MAIL"
        if [ $? != 0 ]; then
            echo "git send fail email failed"
            exit -1
        fi
    fi
}

function quit_test () {
    RET=$1
    local tmp_csv_parse=/tmp/csv_parse_${currsec}
    if [ $RET == 0 ]; then
        STATUS='PASSED'
    else
        STATUS='FAILED'
    fi

    insert_key_to_json "$TEST_STATFILE" test_info end_time "$(date +'%Y-%m-%d %H:%M:%S') ($(date +%s))"
    insert_key_to_json "$TEST_STATFILE" test_info test_result "$STATUS"

    awk -F "\"*,\"*" '{if (NR!=1 && (NF-1)>0) {print $(NF-3), ":", $3}}' "$TEST_REPORT" > $tmp_csv_parse
    
    while read line; do
        array=(${line// : / })
        insert_key_to_json "$TEST_STATFILE" test_report "${array[0]}" "${array[1]}"
    done <$tmp_csv_parse

    rm -f "$tmp_csv_parse" "$TEST_REPORT"
    cat $TEST_STATFILE

    generate_test_mail $STATUS
    exit $RET
}

# Check if lava-tool exists
command -v lava-tool >/dev/null 2>&1 || { echo >&2 "lava-tool required. Aborting."; exit 0; }

insert_key_to_json "$TEST_STATFILE" test_info LAVA_user "$LAVA_USER"
insert_key_to_json "$TEST_STATFILE" test_info LAVA_server "$LAVA_SERVER"
insert_key_to_json "$TEST_STATFILE" test_info LAVA_token "$AUTH_TOKEN"

insert_key_to_json "$TEST_STATFILE" test_info test_suite "$TEST_SUITE"
insert_key_to_json "$TEST_STATFILE" test_info test_device "$TEST_DEVICE"
insert_key_to_json "$TEST_STATFILE" test_info retry_times "$RETRY"

insert_key_to_json "$TEST_STATFILE" test_info kernel "$KERNEL_IMG"
insert_key_to_json "$TEST_STATFILE" test_info rootfs "$ROOTFS"
insert_key_to_json "$TEST_STATFILE" test_info test_image "$TEST_EXPORT_IMAGE"
insert_key_to_json "$TEST_STATFILE" test_info hdd_image "$HDD_IMG"
insert_key_to_json "$TEST_STATFILE" test_info rpm_package "$RPM_PKG"

# Get test job templates and necessary script files
pushd /tmp
lava_test_repo=lava-test_${currsec}

git clone git://ala-lxgit.wrs.com/lpd-ops/lava-test.git "$lava_test_repo"

if [ -d "$lava_test_repo" ]; then
    insert_key_to_json "$TEST_STATFILE" test_info test_git_repo 'git://ala-lxgit.wrs.com/lpd-ops/lava-test.git'

    # LAVA authentication
    echo "[LAVA-CMD] lava-tool auth-list |grep ${LAVA_SERVER}"
    lava-tool auth-list |grep ${LAVA_SERVER}

    # If the auth token exists, remove it
    if [ $? == 0 ]; then
        echo "[LAVA-CMD] lava-tool auth-remove http://${LAVA_USER}@${LAVA_SERVER}"
        lava-tool auth-remove http://${LAVA_USER}@${LAVA_SERVER}

        echo "[LAVA-CMD] lava-tool auth-list |grep ${LAVA_SERVER}"
        lava-tool auth-list |grep ${LAVA_SERVER}
        if [ $? == 0 ]; then
            insert_key_to_json "$TEST_STATFILE" test_info test_result "FAILED: lava-tool auth-remove failed!"
            quit_test -1
        fi
    fi

    # Add new auth token to make sure it's the latest
    echo "[LAVA-CMD] lava-tool auth-add http://${LAVA_USER}:${AUTH_TOKEN}@${LAVA_SERVER}"
    lava-tool auth-add http://${LAVA_USER}:${AUTH_TOKEN}@${LAVA_SERVER}
    
    echo "[LAVA-CMD] lava-tool auth-list |grep ${LAVA_SERVER}"
    lava-tool auth-list |grep ${LAVA_SERVER}
    if [ $? != 0 ]; then
        insert_key_to_json "$TEST_STATFILE" test_info test_result "FAILED: lava-tool auth-add failed!"
        quit_test -1
    fi
else
    insert_key_to_json "$TEST_STATFILE" test_info test_result "FAILED: clone git repo: lava-test failed!"
    quit_test -1
fi

# Set LAVA test job name
TIME_STAMP=`date +%Y%m%d_%H%M%S`
TEST_JOB=test_${TIME_STAMP}.yaml
insert_key_to_json "$TEST_STATFILE" test_info LAVA_test_job "/tmp/${lava_test_repo}/${TEST_JOB}"
insert_key_to_json "$TEST_STATFILE" test_info test_images "${IMAGES_LINK}"

# Replace image files in LAVA JOB file
if [ $TEST_DEVICE == 'simics' ]; then
    JOB_TEMPLATE=${lava_test_repo}/jobs/templates/wrlinux-10/x86_simics_job_${TEST_SUITE}_template.yaml
    cp -f $JOB_TEMPLATE ${lava_test_repo}/${TEST_JOB}
    sed -i "s@HDD_IMG@${HDD_IMG}@g" ${lava_test_repo}/${TEST_JOB}
else
    JOB_TEMPLATE=${lava_test_repo}/jobs/templates/wrlinux-10/x86_64_job_${TEST_SUITE}_template.yaml
    cp -f $JOB_TEMPLATE ${lava_test_repo}/${TEST_JOB}
    sed -i "s@KERNEL_IMG@${KERNEL_IMG}@g" ${lava_test_repo}/${TEST_JOB}
    sed -i "s@ROOTFS@${ROOTFS}@g" ${lava_test_repo}/${TEST_JOB}
fi

# For OE QA test specifically
if [[ $TEST_SUITE == *"oeqa"* ]]; then sed -i "s@TEST_PACKAGE@${TEST_EXPORT_IMAGE}@g" ${lava_test_repo}/${TEST_JOB}
    sed -i "s@MANIFEST_FILE@${MANIFEST_FILE}@g" ${lava_test_repo}/${TEST_JOB}
    sed -i "s@RPM_FILE@${RPM_PKG}@g" ${lava_test_repo}/${TEST_JOB}
fi
#cat ${lava_test_repo}/${TEST_JOB}

if [ -z $RETRY ]; then
    $RETRY=0;
fi

for r in {0..$RETRY}
do
    # Submit an example job
    echo "[LAVA-CMD] lava-tool submit-job http://${LAVA_USER}@${LAVA_SERVER} ${lava_test_repo}/${TEST_JOB}"
    ret=`lava-tool submit-job http://${LAVA_USER}@${LAVA_SERVER} ${lava_test_repo}/${TEST_JOB}`
    job_id=`echo $ret | sed "s/submitted as job: http:\/\/${LAVA_SERVER}\/scheduler\/job\///g"`
    
    if [ -z ${job_id} ]; then
        insert_key_to_json "$TEST_STATFILE" test_info test_result "FAILED: job_id = ${job_id}, failed to submit LAVA job!"
        quit_test -1
    else
        insert_key_to_json "$TEST_STATFILE" test_info LAVA_test_job_id "$job_id"
    fi
    
    echo "[LAVA-CMD] lava-tool job-details http://${LAVA_USER}@${LAVA_SERVER} ${job_id}"
    lava-tool job-details http://${LAVA_USER}@${LAVA_SERVER} ${job_id}
    
    # Echo LAVA job links
    insert_key_to_json "$TEST_STATFILE" test_info test_job_def "http://${LAVA_SERVER}/scheduler/job/${job_id}/definition"
    insert_key_to_json "$TEST_STATFILE" test_info test_log "http://${LAVA_SERVER}/scheduler/job/${job_id}"
    insert_key_to_json "$TEST_STATFILE" test_info test_report "http://${LAVA_SERVER}/results/${job_id}"
    
    # Loop 600 x 10s to wait test result
    for c in {1..600}
    do  
       ret=`lava-tool job-status http://${LAVA_USER}@${LAVA_SERVER} ${job_id} |grep 'Job Status: '`
       job_status=`echo $ret | sed 's/Job Status: //g'`  
       echo "$c. Job Status: $job_status"
       if [ $job_status == 'Complete' ]; then
           insert_key_to_json "$TEST_STATFILE" test_info test_job_status "Completed"

           # Generate test report
           echo "curl http://${LAVA_SERVER}/results/${job_id}/0_${TEST_SUITE}/csv > ${TEST_REPORT}"
           curl http://${LAVA_SERVER}/results/${job_id}/0_${TEST_SUITE}/csv > ${TEST_REPORT}

           if [ -f $TEST_REPORT ]; then
               quit_test 0
           else
               echo "Generate test report file failed!"
               quit_test -1
           fi
       elif [ $job_status == 'Incomplete' ]; then 
           insert_key_to_json "$TEST_STATFILE" test_info test_job_status "Incompleted"
           break;
       elif [ $job_status == 'Canceled' ]; then 
           insert_key_to_json "$TEST_STATFILE" test_info test_job_status "Canceled"
           break;
       elif [ $job_status = 'Submitted' ] || [ $job_status = 'Running' ]; then 
           sleep 10
       fi
    done

    if [ $r -lt $RETRY ]; then
       insert_key_to_json "$TEST_STATFILE" test_info retried_time "$((r + 1))"
    fi
done

# exit with failure or timeout
quit_test -1

