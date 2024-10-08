---
### Upgrade neon-proxy to new version

#### Create DB backup (MANDATORY)

New proxy version requires PostgreSQL 15.6. The previous version used was 14.0. Regardless of which DB version is currently in use, please **CREATE BACKUP**.

#### UPGRADE DB

If you are using our standard solution (PostgreSQL StatefulSet in K8s) and the current PostgreSQL version is 14.0, you can skip this step. 
If you use other solutions, such as AWS RDS, or if the current PostgreSQL version is not 14.0, you need to upgrade your DB on your own. After upgrading, connect to the DB and apply changes [neon-db.sql](https://github.com/neonlabsorg/infrastructure-kubernetes/blob/new_proxy/postgres/files/neon-db.sql).

### Install new proxy version
Clone this repo and checkout to **new_proxy** branch
```bash
git checkout new_proxy
```
#### If DB is already upgraded to 15.6:
```bash
./neon-proxy.sh -f config.ini
```

#### If DB is NOT upgraded and PostgreSQL version is 14.0:

ATTENTION! The **-u** key will run an init container which will create a backup and attempt to upgrade the DB from 14.0 to 15.6. This means that the K8s storage attached to this DB will **consume twice the space**. Please ensure that there is enough free space before running the following command.
```bash
./neon-proxy.sh -u -f config.ini
```
### Check upgrade logs
```bash
kubectl -n neon-proxy logs postgres-0 -c upgrade-postgres
```
If the proxy upgrade is successful, you can connect to the PostgreSQL pod and remove the DB backup. (As a recommendation, if possible, wait a couple of days to ensure system stability.)
```bash
rm -rf /var/lib/postgresql/data/pgdata_14_ver_backup
```