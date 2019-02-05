#!/bin/bash

usage() {
  cat << EOF >&2
Usage: $0 [-u <ip>] [-p <ip> ] [-i <id>] [-t <type>] [-a <ami>] [-s <tar_file>] [-c <yes|no>]

 -u <wrigel-lava-instance ip>: public ip
 -p <wrigel-lava-instance ip>: private ip
 -i <wrigel-lava-instance id>: aws ec2 instance id
   -t <AWS EC2 instance type>: instance type, such as c5.xlarge (default), c5.2xlarge ...
 -a <AWS EC2 AMI information>: without_sstate (default), with_sstate, AMI_ID
-s <sstate-cache-s3-filename>: empty (default to pyro-sato.tar) or the tar file name will copy to S3
 -c <copy-sstate-cache-to-s3>: yes or no (default)
EOF
  exit 1
}

while getopts "u:p:i:t:a:s:c:" opt; do
  case $opt in
    u) jenkins_server_public_ip=$OPTARG
       ;;
    p) jenkins_server_private_ip=$OPTARG
       ;;
    i) jenkins_server_instance_id=$OPTARG
       ;;
    t) jenkins_server_instance_type=$OPTARG
       ;;
    a) jenkins_server_instance_ami=$OPTARG
       ;;
    s) sstate_cache_s3_file_name=$OPTARG
       ;;
    c) copy_sstate_cache_to_s3=$OPTARG
       ;;
    h) usage
       ;;
    *) usage
       ;;
  esac
done
shift "$((OPTIND - 1))"

security_key="wrigel-server.pem"
test_stat_file="/tmp/teststats.json"

if [ -z "$sstate_cache_s3_file_name" ]; then
    sstate_cache_s3_file_name=pyro-sato.tar
fi

function launch_wrigel_instance() {
    jenkins_server_instance_id=$(./launch_ec2_instance.sh -t "$jenkins_server_instance_type" -a "$jenkins_server_instance_ami") 

    local info=$(./get_ec2_instances_info.sh |grep $jenkins_server_instance_id)
    local array=($info)

    jenkins_server_instance_type="${array[1]}"
    jenkins_server_private_ip="${array[3]}"
    jenkins_server_public_ip="${array[4]}"

    echo "jenkins_server_instance_id   = $jenkins_server_instance_id"
    echo "jenkins_server_instance_type = $jenkins_server_instance_type"
    echo "jenkins_server_private_ip    = $jenkins_server_private_ip"
    echo "jenkins_server_public_ip     = $jenkins_server_public_ip"
}

function get_lava_server_public_ip() {
    local info=$(./get_ec2_instances_info.sh -t t2.micro -s running)
    local array=($info)
    lava_server_ip="${array[4]}"
    
    echo "lava_server_public_ip        = $lava_server_ip"
}

function get_wrigel_instance_public_ip() {
    if [ -z "$jenkins_server_instance_id" ]; then
	jenkins_server_public_ip=''
    else
	local info=$(./get_ec2_instances_info.sh | grep "$jenkins_server_instance_id")
        local array=($info)
        jenkins_server_public_ip="${array[4]}"
    fi
    
    echo "jenkins_server_public_ip     = $jenkins_server_public_ip"
}

function get_ec2_pricing() {
    if [ -z "$jenkins_server_instance_type" ]; then
	echo "None"
    else
        local info=$(cat ec2_pricing.txt | grep "$jenkins_server_instance_type")
        local array=($info)
        echo "${array[-3]}"
    fi
}

function terminate_instance() {
    local instance_id=$1
    ./terminate_ec2_instance.sh "$instance_id"
}

function stop_instance() {
    local instance_id=$1
    ./stop_ec2_instance.sh "$instance_id"
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


function check_jenkins_server_status() {
    local get_jenkins_status_cmd="systemctl status start_jenkins.service |grep Active"

    ret=$(ssh -i $security_key -o 'StrictHostKeyChecking no' ubuntu@${jenkins_server_public_ip} $get_jenkins_status_cmd)

    echo $ret
}

function restart_jenkins_service() {
    local restart_jenkins_cmd="sudo systemctl restart start_jenkins.service"
    local restart_lava_server_cmd="sudo systemctl restart start_lava.service"

    echo "Restarting Jenkins service ..."
    ssh -i "$security_key" -o "StrictHostKeyChecking no" ubuntu@${jenkins_server_public_ip} "$restart_jenkins_cmd"
    ssh -i "$security_key" -o "StrictHostKeyChecking no" ubuntu@${jenkins_server_public_ip} "$restart_lava_server_cmd"
    echo "Done"
}

# check if jenkins server is ready to use
function check_jenkins_home() {
    local get_next_build_number="docker exec ci_jenkins_1 cat /var/jenkins_home/jobs/WRLinux_Build/nextBuildNumber"

    echo "Getting Jenkins next build number ..."
    ret=$(ssh -i $security_key -o 'StrictHostKeyChecking no' ubuntu@${jenkins_server_public_ip} $get_next_build_number)

    echo "$ret"
}

function get_lava_auth_token() {
    local get_auth_token_cmd="docker exec lava-server lava-server manage tokens list --user lpdtest"
    local auth_token=/tmp/auth_token

    echo "Getting LAVA auth token ..."
    ssh -i $security_key -o 'StrictHostKeyChecking no' ubuntu@${jenkins_server_public_ip} "$get_auth_token_cmd" > "$auth_token"
    ret=$(cat "$auth_token" | tail -1)
    lava_auth_token=${ret:2:-2}

    if [ -z "$lava_auth_token" ]; then
        echo "Can't get auth token, exit!"
	exit 1
    else
        echo "$lava_auth_token"
    fi
}

function set_device_ip() {
    # setup qemu deivce with using jenkins_server_public_ip
    local lava_qemu_device=/etc/lava-server/dispatcher-config/devices/x86_64_aws-ec2_qemu01.jinja2
    local set_device_ip_cmd="docker exec lava-server sed -i '/set host_ip/c\{% set host_ip = \x27'$jenkins_server_private_ip'\x27 %}' $lava_qemu_device"
    local check_device_ip_cmd="docker exec lava-server cat $lava_qemu_device |grep 'set host_ip'"

    ssh -i wrigel-server.pem -o "StrictHostKeyChecking no" ubuntu@${jenkins_server_public_ip} "$set_device_ip_cmd"
    ssh -i wrigel-server.pem -o "StrictHostKeyChecking no" ubuntu@${jenkins_server_public_ip} "$check_device_ip_cmd"
}

function set_dispatcher_ip() {
    local docker_cmd="echo dispatcher_ip: $jenkins_server_private_ip > /etc/lava-server/dispatcher.d/dispatcher01.yaml"
    local set_dispatcher_ip_cmd="docker exec lava-server bash -c '$docker_cmd'"
    local check_dispatcher_ip_cmd="docker exec lava-server cat /etc/lava-server/dispatcher.d/dispatcher01.yaml"

    ssh -i wrigel-server.pem -o "StrictHostKeyChecking no" ubuntu@${jenkins_server_public_ip} "$set_dispatcher_ip_cmd"
    ssh -i wrigel-server.pem -o "StrictHostKeyChecking no" ubuntu@${jenkins_server_public_ip} "$check_dispatcher_ip_cmd"
}

function set_ssh_token_for_lava_dispatcher() {
    local ssh_keygen_cmd="docker exec lava-dispatcher ssh-keygen -f /root/.ssh/id_rsa -t rsa -N ''"
    local update_local_pubkey_cmd="docker exec lava-dispatcher cat /root/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys"

    ssh -i wrigel-server.pem -o "StrictHostKeyChecking no" ubuntu@${jenkins_server_public_ip} "$ssh_keygen_cmd"
    ssh -i wrigel-server.pem -o "StrictHostKeyChecking no" ubuntu@${jenkins_server_public_ip} "$update_local_pubkey_cmd"
}

function get_number_of_running_dockers() {
    local docker_cmd="docker ps | wc -l"

    echo "Getting running ci dockers number ..."
    number_of_running_dockers=$(ssh -i $security_key -o 'StrictHostKeyChecking no' ubuntu@${jenkins_server_public_ip} $docker_cmd)

    echo "$number_of_running_dockers"
}

function check_test_result() {
    local RSYNC_DEST_DIR=$1
    local test_stat_url="https://${jenkins_server_public_ip}/${RSYNC_DEST_DIR}/teststats.json"

    if [ -f "$test_stat_file" ]; then
	rm -f "$test_stat_file"
    fi
    
    wget -q --no-check-certificate "$test_stat_url" -O "$test_stat_file"

    if [ -f "$test_stat_file" ]; then
	test_result=$(cat "$test_stat_file" |grep test_result)
	if [ -n "$test_result" ]; then
            cat "$test_stat_file"
        fi
    fi
}

function do_copy_sstate_cache_to_s3() {
    local cleanup_sstate_cache="cd /opt && find sstate_cache -name 'sstate*' -mtime +2 -delete"
    local compress_sstate_cache="cd /opt && rm -rf tmp/* && tar cf tmp/${sstate_cache_s3_file_name} sstate_cache"
    local copy_sstate_cache_to_s3="aws s3 cp /opt/tmp/${sstate_cache_s3_file_name} s3://s3-sstate-cache/"
    local list_sstate_cache_in_s3="aws s3 ls s3://s3-sstate-cache/"

    echo "Clean up sstate_cache folder ..."
    ssh -i wrigel-server.pem -o "StrictHostKeyChecking no" ubuntu@${jenkins_server_public_ip} "$cleanup_sstate_cache"
    echo "Pack it up ..."
    ssh -i wrigel-server.pem -o "StrictHostKeyChecking no" ubuntu@${jenkins_server_public_ip} "$compress_sstate_cache"
    echo "Copy it to s3 ..."
    ssh -i wrigel-server.pem -o "StrictHostKeyChecking no" ubuntu@${jenkins_server_public_ip} "$list_sstate_cache_in_s3"
    ssh -i wrigel-server.pem -o "StrictHostKeyChecking no" ubuntu@${jenkins_server_public_ip} "$copy_sstate_cache_to_s3"
    ssh -i wrigel-server.pem -o "StrictHostKeyChecking no" ubuntu@${jenkins_server_public_ip} "$list_sstate_cache_in_s3"
    echo "Done!"
}

function copy_sstate_cache_from_s3() {
    local copy_sstate_cache_cmd="aws s3 cp s3://s3-sstate-cache/${sstate_cache_s3_file_name} /opt/tmp/"
    local extract_sstate_cache_cmd="cd /opt/tmp/ && tar xf ${sstate_cache_s3_file_name} && rm -rf /opt/sstate_cache/* && mv sstate_cache/* /opt/sstate_cache"

    echo "Copy sstate_cache tar file from s3 to /opt/tmp ..."
    ssh -i wrigel-server.pem -o "StrictHostKeyChecking no" ubuntu@${jenkins_server_public_ip} "$copy_sstate_cache_cmd"
    echo "Extract sstate_cache files to /opt/sstate_cache ..."
    ssh -i wrigel-server.pem -o "StrictHostKeyChecking no" ubuntu@${jenkins_server_public_ip} "$extract_sstate_cache_cmd"
    echo "Done!"
}

timestamp=$(date +%Y%m%d_%H%M)
start_sec=$(date +%s)

# get lava-server ip
#if [ -z $lava_server_ip ]; then
#    get_lava_server_public_ip
#
#    if [ -z "$lava_server_ip" ] || [[ "$lava_server_ip" == 'None' ]]; then
#	echo "Can't get LAVA server IP, exit!"
#	exit
#    fi
#fi

# get wrigel instance info
if [ -z $jenkins_server_public_ip ]; then
    # launch a new wrigel instance
    launch_wrigel_instance
    show_sleep_progress 1 90

    for i in 1 2 3
    do
	if [ -z "$jenkins_server_public_ip" ] || [[ "$jenkins_server_public_ip" == 'None' ]]; then
            show_sleep_progress 1 30
	    get_wrigel_instance_public_ip
	else
	    break
        fi
    done
fi

lava_server_ip="${jenkins_server_public_ip}:8080"

for i in 1 2 3 4 5
do
    ret=$(check_jenkins_server_status)
    get_number_of_running_dockers
    if [[ "$ret" == *"running"* ]] && [[ "$number_of_running_dockers" -ge 9 ]]; then
	echo "Jenkins service is running ..."

	# check if jenkins server is ready to start
        check_jenkins_home

        if [ "$ret" -ge 1 ]; then
            echo "Jenkins server is ready to start!"
	    break
        else
            echo "Jenkins server is not ready"
            show_sleep_progress $i 30
        fi
    else
	if [[ $i == 5 ]]; then
	    echo "Jenkins server is not running properly, exit!"
	    echo "$jenkins_server_status"

            # terminate the wrigel instance
            terminate_instance "$jenkins_server_instance_id"
	    exit
        else	
            #restart_jenkins_service
            show_sleep_progress $i 30
	fi
    fi
done

# get lava auth token
get_lava_auth_token

# set device ip in lava-server
set_device_ip

# set dispatcher ip for lava-server
set_dispatcher_ip

# set ssh token for lava-server so that lava-device can run commands from host
set_ssh_token_for_lava_dispatcher

# copy sstate_cache from s3 to local
copy_sstate_cache_from_s3

# submit a jenkins job
RSYNC_DEST_DIR=builds/pyro-sato-${timestamp}
jenkins_job_submit_cmd="cd /opt/ci-scripts && \
.venv/bin/python3 ./jenkins_job_submit.py \
--configs_file configs/OpenEmbedded/jenkins_job_configs.yaml \
--postprocess_args=RSYNC_DEST_DIR="$RSYNC_DEST_DIR" \
--jenkins https://${jenkins_server_public_ip} \
--test_args=LAVA_SERVER=${lava_server_ip},RETRY=1,LAVA_AUTH_TOKEN=${lava_auth_token}"

echo ========= WRIGEL job submit ==========
echo -e "$jenkins_job_submit_cmd" | sed 's/--/\\\n--/g'
echo ======================================

ssh -i wrigel-server.pem -o "StrictHostKeyChecking no" ubuntu@${jenkins_server_public_ip} "$jenkins_job_submit_cmd"

echo "==========Test Started: $timestamp==========="

for i in {1..480}
do
    ret=$(check_test_result "$RSYNC_DEST_DIR")
    if [ -n "$ret" ]; then
	echo "$ret"
	break
    fi
    show_sleep_progress $i 60
done

# check test result
test_result=$(cat $test_stat_file | grep test_result)
echo "$test_result"
if [[ "$test_result" == *"FAILED"* ]]; then
    # stop the wrigel instance
    stop_instance "$jenkins_server_instance_id"
else
    if [[ "$copy_sstate_cache_to_s3" == 'yes' ]]; then
        do_copy_sstate_cache_to_s3
    fi
    # terminate the wrigel instance
    terminate_instance "$jenkins_server_instance_id"
fi

timestamp=$(date +%Y%m%d_%H%M)
end_sec=$(date +%s)

duration=$(((end_sec - $start_sec)/60))
ec2_pricing=$(get_ec2_pricing)
price=`bc <<< "scale=4; ${ec2_pricing:1} * $duration / 60" | awk '{printf "%.4f", $0}'`

echo "$jenkins_server_instance_type instance:"
echo "   - Pricing         : $ec2_pricing/hour"
echo "   - Used            : $duration minutes"
echo "   - Estimated price : \$$price"
echo "==========Test Ended: $timestamp==========="

