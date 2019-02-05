#!/bin/bash

usage() {
  cat << EOF >&2
Usage: $0 [-s <state>] [-t <type>]

-s <state>: instance state, such as running, stopped, terminated ...
 -t <type>: instance type, such as t2.micro, c5.xlarge, c5.2xlarge ...
EOF
  exit 1
}

itype=""
istate=""

while getopts "s:t:h:" opt; do
  case $opt in
    s) istate=$OPTARG
       ;;
    t) itype=$OPTARG
       ;;
    h) usage
       ;;
    *) usage
       ;;
  esac
done
shift "$((OPTIND - 1))"

#echo Remaining arguments: "$@"
#echo "Filter: Type=$itype, State=$istate"

if [[ -z $itype ]] && [[ -n $istate ]]; then
    FILTER="--filters Name=instance-state-name,Values=$istate"
elif [[ -n $itype ]] && [[ -z $istate ]]; then
    FILTER="--filters Name=instance-type,Values=$itype"
elif [[ -n $itype ]] && [[ -n $istate ]]; then
    FILTER="--filters Name=instance-state-name,Values=$istate Name=instance-type,Values=$itype"
elif [[ -z $itype ]] && [[ -z $istate ]]; then
    FILTER=""
fi

#echo "FILTER=$FILTER"

aws ec2 describe-instances \
$FILTER \
--query "Reservations[].Instances[].[InstanceId,InstanceType,State.Name,PrivateIpAddress,PublicIpAddress,Tags[?Key=='Name'].Value[]]" \
--output json | tr -d '\n[] "' | perl -pe 's/i-/\ni-/g' | tr ',' '\t' | sed -e 's/null/None/g' | grep '^i-' | column -t \
#--filters Name=instance-state-name,Values=running \

