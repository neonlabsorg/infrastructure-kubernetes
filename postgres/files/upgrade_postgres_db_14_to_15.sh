#!/bin/bash
# Exit script on any error
set -e

# Check PostgreSQL version
PG_VERSION_FILE="/var/lib/postgresql/data/pgdata/PG_VERSION"


if [ ! -f "$PG_VERSION_FILE" ]; then
  echo "===================="
  echo "PostgreSQL version file not found. Please check if the database is in the correct directory."
  echo "===================="
  exit 1
fi

PG_VERSION=$(cat "$PG_VERSION_FILE")

# If version is not 14 or 15, exit with error
if [ "$PG_VERSION" != "14" ] && [ "$PG_VERSION" != "15" ]; then
  echo "===================="
  echo "Unexpected PostgreSQL version "${PG_VERSION}". Manual database upgrade is required."
  echo "===================="
  exit 1
fi

# If version is 15, DB is already updated
if [ "$PG_VERSION" == "15" ]; then
  echo "Database is already upgraded to PostgreSQL 15."
  exit 0
fi

upgrade_db() {
  set -e
  echo "===================="
  echo "Creating backup"
  echo "===================="
  if ! mv /var/lib/postgresql/data/pgdata /var/lib/postgresql/data/pgdata_14_ver_backup; then
      echo "Backup already exists, possibly from a previous upgrade attempt. You might need to manually remove '/var/lib/postgresql/data/pgdata_14_ver_backup' or proceed with the upgrade manually."
      return 1
  fi
  mkdir /var/lib/postgresql/data/pgdata || return 1
  chmod 0750 /var/lib/postgresql/data/pgdata_14_ver_backup || return 1

  echo "===================="
  echo "Init new DB"
  echo "===================="
  /usr/lib/postgresql/15/bin/initdb -D /var/lib/postgresql/data/pgdata \
    --encoding=UTF8 --lc-collate='en_US.utf8' --lc-ctype='en_US.utf8' || return 1

  echo "===================="
  echo "Run postgres 14"
  echo "===================="
  /usr/lib/postgresql/14/bin/pg_ctl start -D /var/lib/postgresql/data/pgdata_14_ver_backup \
    -o "-p 50432 -c listen_addresses='' -c unix_socket_permissions=0700 -c unix_socket_directories='/var/lib/postgresql'" || return 1

  echo "===================="
  echo "Run postgres 15"
  echo "===================="
  /usr/lib/postgresql/15/bin/pg_ctl start -D /var/lib/postgresql/data/pgdata \
    -o "-p 50433 -c listen_addresses='' -c unix_socket_permissions=0700 -c unix_socket_directories='/var/lib/postgresql'" || return 1

  echo "===================="
  echo "Stop postgres 14"
  echo "===================="
  /usr/lib/postgresql/14/bin/pg_ctl stop -D /var/lib/postgresql/data/pgdata_14_ver_backup || return 1

  echo "===================="
  echo "Stop postgres 15"
  echo "===================="
  /usr/lib/postgresql/15/bin/pg_ctl stop -D /var/lib/postgresql/data/pgdata || return 1

  echo "===================="
  echo "Check the possibility of updating"
  echo "===================="
  /usr/lib/postgresql/15/bin/pg_upgrade \
    --old-datadir=/var/lib/postgresql/data/pgdata_14_ver_backup \
    --new-datadir=/var/lib/postgresql/data/pgdata \
    --old-bindir=/usr/lib/postgresql/14/bin \
    --new-bindir=/usr/lib/postgresql/15/bin \
    --old-port=50432 \
    --new-port=50433 \
    --check || return 1

  echo "===================="
  echo "Update DB to 15 ver"
  echo "===================="
  /usr/lib/postgresql/15/bin/pg_upgrade \
    --old-datadir=/var/lib/postgresql/data/pgdata_14_ver_backup \
    --new-datadir=/var/lib/postgresql/data/pgdata \
    --old-bindir=/usr/lib/postgresql/14/bin \
    --new-bindir=/usr/lib/postgresql/15/bin \
    --old-port=50432 \
    --new-port=50433 || return 1
}


revert_db_upgrade() {
  set -e
  echo "===================="
  echo "Restoring DB from backup"
  echo "===================="
  rm -rf /var/lib/postgresql/data/pgdata
  mv /var/lib/postgresql/data/pgdata_14_ver_backup /var/lib/postgresql/data/pgdata || return 1
  chmod 0750 /var/lib/postgresql/data/pgdata /var/lib/postgresql/data/pgdata || return 1

  echo "PostgresDB has been restored to ver "${PG_VERSION}""
}

# Execute the upgrade
echo "===================="
if ! upgrade_db; then    
  revert_db_upgrade
  echo "Something went wrong during the upgrade process, check the above logs."
  exit 1
else
  echo "Postgres DB has been updated successfully"
fi