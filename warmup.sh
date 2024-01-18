#!/bin/bash

ulimit -n 4086

sysbench \
  --db-driver=pgsql \
  --pgsql-host=${pgsql_host} \
  --pgsql-user=${pgsql_user} \
  --pgsql-port=${pgsql_port} \
  --pgsql-password=${pgsql_password} \
  --pgsql-db=${pgsql_db} \
  --db-ps-mode=auto \
  --tables=100 \
  --rand-type=uniform \
  --table-size=20000000 \
  --percentile=99 \
  --report-interval=1 \
  --time=15 \
  --threads=32 \
  oltp_read_only \
  run
