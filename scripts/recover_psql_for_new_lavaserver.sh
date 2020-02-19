#!/bin/bash

if [ -z $1 ]; then
    echo "Shared volume is set to '/var/lib/tftpboot'"
    volume='/var/lib/tftpboot'
else
    volume=$1
fi

echo "Recover database in standalone lava-server ..."

# Copy the backup database 'lavaserver.db' into docker
docker cp "${volume}/postgresql/lavaserver.db" lava-server:/var/lib/postgresql
# Here 'scripts/loaddb.sh' is inside lava-ci repo
docker cp scripts/loaddb.sh lava-server:/var/lib/postgresql
# Inside docker, clean up original lavaserver database and load the backup one
docker exec lava-server su - postgres -s /bin/bash -c '/var/lib/postgresql/loaddb.sh'
# Copy backed up database folder to host
docker cp lava-server:/var/lib/postgresql/11.tar "${volume}/postgresql"
# On the host side, extract the backup database folder and set its owner properly, 
# make it ready to be used for volume mapping
cd "${volume}/postgresql" 

if [ -d 11_bak ]; then 
    sudo rm -rf 11_bak; 
fi
if [ -d 11 ]; then 
    sudo mv 11 11_bak; 
fi

tar xf 11.tar
# Set uid and gid proply, reference: 
# https://stackoverflow.com/questions/26500270/understanding-user-file-ownership-in-docker-how-to-avoid-changing-permissions-o
uid_gid=$(docker exec lava-server stat -c "%u:%g" /var/lib/postgresql/11)

sudo chown -R "$uid_gid" 11
cd -

echo "DONE"

# recover logs

echo "Recover console logs in standalone lava-server ..."

docker exec lava-server bash -c 'if [ -d /var/lib/lava-server/default ]; then rm -rf /var/lib/lava-server/default; fi'

echo "...Copy backup default.tar into docker ..."

docker cp ${volume}/lava-server/default.tar lava-server:/var/lib/lava-server

echo "...Extract default.tar to /var/lib/lava-server ..."

docker exec lava-server tar xf /var/lib/lava-server/default.tar --directory /var/lib/lava-server

echo "...Change owner of /var/lib/lava-server/default to lavaserver:lavaserver ..."

docker exec lava-server chown -R lavaserver:lavaserver /var/lib/lava-server/default

echo "DONE"
echo "You can do some test in lava-server docker now."

# restore the logs folder back to host

echo "Copy recovered console logs back to host ..."

docker exec lava-server rm -rf /var/lib/lava-server/default.tar

echo "...Compress /var/lib/lava-server/default to a tar file ..."

docker exec lava-server bash -c "cd /var/lib/lava-server; tar cf default.tar default; cd -"

echo "...Remove original default.tar on host ..."

sudo rm -rf ${volume}/lava-server/default.tar ${volume}/lava-server/default

echo "...Copy generated default.tar back to host ..."

sudo docker cp lava-server:/var/lib/lava-server/default.tar ${volume}/lava-server/

echo "...Extract default.tar on host ..."

cd ${volume}/lava-server; sudo tar xf default.tar; cd -

echo "DONE"
echo "Now you are ready to restart new LAVA server with volume mapping."
