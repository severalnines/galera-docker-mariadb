#!/bin/bash
# Report Galera status to etcd periodically.
# report_status.sh [mysql user] [mysql password] [cluster name] [interval] [comma separated etcd hosts]
# Example: 
# report_status.sh root myS3cret galera_cluster 15 192.168.55.111:2379,192.168.55.112:2379,192.168.55.113:2379

USER=$1
PASSWORD=$2
CLUSTER_NAME=$3
TTL=$4
ETCD_HOSTS=$5

function check_etcd()
{
  etcd_hosts=$(echo $ETCD_HOSTS | tr ',' ' ')
  flag=1

  # Loop to find a healthy etcd host
  for i in $etcd_hosts
  do
    curl -s http://$i/health > /dev/null || continue
    if curl -s http://$i/health | jq -e 'contains({ "health": "true"})' > /dev/null; then
      healthy_etcd=$i
      flag=0
      break
    fi
  done

  # Flag is 0 if there is a healthy etcd host
  [ $flag -ne 0 ] && echo "report>> Couldn't reach healthy etcd nodes."
}

function report_status()
{
  var=$1

  if [ ! -z $var ]; then
    check_etcd
    
    URL="http://$healthy_etcd/v2/keys/galera/$CLUSTER_NAME"
    output=$(mysql --user=$USER --password=$PASSWORD -A -Bse "show status like '$var'" 2> /dev/null)
    key=$(echo $output | awk {'print $1'})
    value=$(echo $output | awk {'print $2'})
    ipaddr=$(hostname -i | awk {'print $1'})

    if [ ! -z $value ]; then
      curl -s $URL/$ipaddr/$key -X PUT -d "value=$value&ttl=$TTL" > /dev/null
    fi
  fi
  
}

while true;
do
  report_status wsrep_local_state_comment
  report_status wsrep_last_committed
  # report every ttl - 2 to ensure value does not expired
  sleep $(($TTL - 2))
done
