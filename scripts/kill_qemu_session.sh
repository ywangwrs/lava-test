if [[ -z $1 ]]; then
    echo "Please input session id"
    exit 0
fi

session_id=$1
ps -ef | grep [:]$session_id 

pid=$(ps -ef | grep [:]$session_id | awk '{print $2}')
kill $pid
