#!/bin/bash

sysbench \
  --db-driver=pgsql \
  --pgsql-host=${pgsql_host} \
  --pgsql-port=${pgsql_port} \
  --pgsql-user=${pgsql_user} \
  --pgsql-password=${pgsql_password} \
  --pgsql-db=${pgsql_db} \
  --tables=100 \
  --table-size=20000000 \
  --threads=16 \
  oltp_read_write \
  prepare
