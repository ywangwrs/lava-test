#!/bin/bash

# backup database

if [ -z $1 ]; then
    echo "Usage: $0 <backup_dir>"
    exit
fi

backup_dir=$1

echo "Backup database inside lava-server..."

docker exec lava-server su - postgres -s /bin/bash -c 'pg_dump lavaserver > /var/lib/postgresql/10/lavaserver.db'

cp ${backup_dir}/postgresql/lavaserver.db ${backup_dir}/postgresql/lavaserver_`date +%Y%m%d`.db

docker cp lava-server:/var/lib/postgresql/10/lavaserver.db ${backup_dir}/postgresql

echo "DONE"

ls -la ${backup_dir}/postgresql

# backup previous logs

echo "Backup console logs..."

cd ${backup_dir}/lava-server && sudo tar cf default.tar default && sudo cp default.tar default_`date +%Y%m%d`.tar  && cd -

echo "DONE"

ls -la ${backup_dir}/lava-server
