#!/bin/bash

cd /var/lib/postgresql

# List postgres database's, it should contain 'lavaserver'
psql -c "\l"

# Get pid of current running 'lavaserver' database
pid=$(ps -A -o pid,cmd|grep lavaserver | grep -v grep |head -n 1 | awk '{print $1}')
if [ -z "$pid" ]; then
    echo "Can't find lavaserver process' pid, exit!"
    exit 1
else
    echo "pid = $pid"
fi

# Terminate current 'lavaserver' database and drop (delete it)
#psql -c "SELECT pg_terminate_backend($pid)FROM pg_stat_activity WHERE pid <> pg_backend_pid() AND datname = 'lavaserver';" && psql -c "DROP DATABASE lavaserver;"
pg_ctlcluster 11 main restart --force
dropdb lavaserver

# List postgres database's again, 'lavaserver' should not exist anymore
psql -c "\l"

# Recreate 'lavaserver' database
createdb lavaserver

# Restore its content from a backup database file
psql lavaserver < lavaserver.db

# Packup database folder and ready to copy it outside of docker
tar cf 11.tar 11
