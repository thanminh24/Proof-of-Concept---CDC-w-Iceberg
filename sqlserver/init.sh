#!/bin/bash
apt-get update &&
apt-get install -y curl gnupg &&
curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add - &&
curl https://packages.microsoft.com/config/ubuntu/20.04/prod.list > /etc/apt/sources.list.d/mssql-release.list &&
apt-get update &&
ACCEPT_EULA=Y apt-get install -y mssql-tools18 &&
echo "Waiting for SQL Server to start..." &&
/opt/mssql/bin/sqlservr &
counter=0
max_retries=150
while [ $counter -lt $max_retries ]; do
  if /opt/mssql-tools18/bin/sqlcmd -S localhost -U SA -P YourStrongPassword123! -Q "SELECT 1" -C > /sqlcmd.log 2>&1; then
    echo "SQL Server is ready, running init.sql..." &&
    /opt/mssql-tools18/bin/sqlcmd -S localhost -U SA -P YourStrongPassword123! -i /init.sql -C > /init.log 2>&1 &&
    echo "init.sql executed successfully" &&
    wait
    exit 0
  fi
  counter=$((counter + 1))
  echo "Waiting for SQL Server ($counter/$max_retries)..." &&
  sleep 2
done
echo "Error: SQL Server did not start in time" &&
cat /sqlcmd.log &&
exit 1

