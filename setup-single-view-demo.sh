#!/bin/bash

# Common Vars
SCRIPT_NAME=$(basename $0)
SCRIPT_DIR=$(cd `dirname $0` && pwd)

# Lab password
LAB_PW='Welcome2lab!'

# Sanity Checks
if [ $(id -un) != "root" ]; then
  echo "ERROR: Must be run as root. Run sudo su - before running this script"
  exit 1
fi

#
#
#
check_rc () {
  if [ $1 -ne 0 ]; then
    echo "ERROR"
    exit 1
  else
    echo "SUCCESS"
  fi
}

#
# Main
#

# Set the Ambari server password
echo -e "\n### Prompting the user for the Ambari server admin password"
/usr/sbin/ambari-admin-password-reset
check_rc $?

# Add zeppelin to sudoers
echo -e "\n### Adding the zeppelin user to sudoers: "
echo "zeppelin  ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
check_rc $?

# Allow zeppelin to access postgres
echo -e "\n### Setup postgres access for zeppelin"
echo "host all all 127.0.0.1/32 md5" >> /var/lib/pgsql/data/pg_hba.conf
check_rc $?

# Add zeppelin to the HDFS group
echo -e "\n### Adding the zeppelin user to the hdfs group"
usermod -G hdfs zeppelin
check_rc $?

# Setup the zeppelin password file for SQOOP
echo -e "\n### Creating the zeppelin password file for SQOOP"
echo -n "zeppelin" > /home/zeppelin/.password
hdfs dfs -put /home/zeppelin/.password /user/zeppelin/
check_rc $?
rm /home/zeppelin/.password

# Download the latest zeppelin notebooks
echo -e "\n### Downloading and installing zeppelin notebooks"
curl -sSL https://raw.githubusercontent.com/hortonworks-gallery/zeppelin-notebooks/master/update_all_notebooks.sh | sudo -u zeppelin -E sh
check_rc $?

# Download the latest code from the git repo
echo -e "\n### Downloading the latest single view demo code"
cd /home/zeppelin && sudo -u zeppelin -E git clone https://github.com/abajwa-hw/single-view-demo.git
check_rc $?

# Restart Ambari-agent
echo -e "\n### Restarting ambari-agent"
service ambari-agent stop
service ambari-agent start
check_rc $?

# Restart postgres
echo -e "\n### Restarting postgres"
service postgresql stop
service postgresql start
check_rc $?

# Configure SQOOP for Postgres
echo -e "\n### Configuring SQOOP for Postgres"
sudo wget https://jdbc.postgresql.org/download/postgresql-9.4.1207.jar -P /usr/hdp/current/sqoop-client/lib
check_rc $?

# Download the contoso dataset
echo -e "\n### Downloading the contoso data set"
cd /tmp && wget https://www.dropbox.com/s/r70i8j1ujx4h7j8/data.zip && unzip data.zip
check_rc $?

# Create the contoso database
echo -e "\n### Creating Postgres database contoso"
sudo -u postgres psql -c "create database contoso;"
sudo -u postgres psql -c "CREATE USER zeppelin WITH PASSWORD 'zeppelin';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE contoso to zeppelin;"
sudo -u postgres psql -c "\du"
check_rc $?

# Load the contoso data into Postgres
echo -e "\n### Loading the contoso data into Postgres... this will take a while"
export PGPASSWORD=zeppelin
psql -U zeppelin -d contoso -h localhost -f /home/zeppelin/single-view-demo/contoso-psql.sql
check_rc $?

# Increase the amount of memory available to YARN
echo -e "\n### Increasing the amount of memory allocated to YARN"
/var/lib/ambari-server/resources/scripts/configs.sh -u admin -p $LAB_PW set localhost Sandbox yarn-site "yarn.nodemanager.resource.memory-mb" "8192"
check_rc $?

# Set hive.tez.container.size to avoid OOM
echo -e "\n### Setting hive.tez.container.size to 1GB to avoid OOM"
/var/lib/ambari-server/resources/scripts/configs.sh -u admin -p $LAB_PW set localhost Sandbox hive-site "hive.tez.container.size" "2048"
check_rc $?

# Start Hive mysql
echo -e "\n### Starting up Hive's mysql instance"
export SERVICE=HIVE
export AMBARI_HOST=localhost
export CLUSTER=Sandbox
curl -u admin:$LAB_PW -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Start Hive via REST"}, "Body": {"ServiceInfo": {"state": "STARTED"}}}'  http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER/services/$SERVICE && sleep 60
check_rc $?

# Restart hive
echo -e "\n### Restarting Hive for hive.tez.container.size change"
export SERVICE=HIVE
export AMBARI_HOST=localhost
export CLUSTER=Sandbox
curl -u admin:$LAB_PW -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Stop Hive via REST"}, "Body": {"ServiceInfo": {"state": "INSTALLED"}}}'  http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER/services/$SERVICE && sleep 60
curl -u admin:$LAB_PW -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Start Hive via REST"}, "Body": {"ServiceInfo": {"state": "STARTED"}}}'  http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER/services/$SERVICE && sleep 300
check_rc $?

# Restart oozie
echo -e "\n### Restarting Oozie for hive.tez.container.size change"
export SERVICE=OOZIE
export AMBARI_HOST=localhost
export CLUSTER=Sandbox
curl -u admin:$LAB_PW -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Stop Oozie via REST"}, "Body": {"ServiceInfo": {"state": "INSTALLED"}}}'  http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER/services/$SERVICE && sleep 120
curl -u admin:$LAB_PW -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Start Oozie via REST"}, "Body": {"ServiceInfo": {"state": "STARTED"}}}'  http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER/services/$SERVICE && sleep 60
check_rc $?

# Restart yarn
echo -e "\n### Restarting YARN for nodemanager memory change"
export SERVICE=YARN
export AMBARI_HOST=localhost
export CLUSTER=Sandbox
curl -u admin:$LAB_PW -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Stop YARN via REST"}, "Body": {"ServiceInfo": {"state": "INSTALLED"}}}'  http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER/services/$SERVICE && sleep 120
curl -u admin:$LAB_PW -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Start YARN via REST"}, "Body": {"ServiceInfo": {"state": "STARTED"}}}'  http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER/services/$SERVICE && sleep 60
check_rc $?

# Restart MapReduce2
echo -e "\n### Restarting YARN for nodemanager memory change"
export SERVICE=MAPREDUCE2
export AMBARI_HOST=localhost
export CLUSTER=Sandbox
curl -u admin:$LAB_PW -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Stop MapReduce2 via REST"}, "Body": {"ServiceInfo": {"state": "INSTALLED"}}}'  http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER/services/$SERVICE && sleep 120
curl -u admin:$LAB_PW -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Start MapReduce2 via REST"}, "Body": {"ServiceInfo": {"state": "STARTED"}}}'  http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER/services/$SERVICE && sleep 60
check_rc $?

# Restart Tez
echo -e "\n### Restarting Tez for nodemanager memory change"
export SERVICE=TEZ
export AMBARI_HOST=localhost
export CLUSTER=Sandbox
curl -u admin:$LAB_PW -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Stop Tez via REST"}, "Body": {"ServiceInfo": {"state": "INSTALLED"}}}'  http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER/services/$SERVICE && sleep 120
curl -u admin:$LAB_PW -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Start Tez via REST"}, "Body": {"ServiceInfo": {"state": "STARTED"}}}'  http://$AMBARI_HOST:8080/api/v1/clusters/$CLUSTER/services/$SERVICE && sleep 60
check_rc $?

exit 0
