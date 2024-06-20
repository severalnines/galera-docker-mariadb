#!/bin/bash
set -e

touch /entrypoint.executing

# if command starts with an option, prepend mysqld
if [ "${1:0:1}" = '-' ]; then
	CMDARG="$@"
fi

[ -z "$TTL" ] && TTL=10

if [ -z "$CLUSTER_NAME" ]; then
	echo >&2 'Error:  You need to specify CLUSTER_NAME'
	exit 1
fi
	# Get config
	DATADIR="$("mysqld" --verbose --help 2>/dev/null | awk '$1 == "datadir" { print $2; exit }')"
	echo >&2 "Content of $DATADIR:"
	ls -al $DATADIR

	if [ ! -s "$DATADIR/grastate.dat" ]; then
		INITIALIZED=1
		if [ -z "$MYSQL_ROOT_PASSWORD" -a -z "$MYSQL_ALLOW_EMPTY_PASSWORD" -a -z "$MYSQL_RANDOM_ROOT_PASSWORD" ]; then
                        echo >&2 'error: database is uninitialized and password option is not specified '
                        echo >&2 '  You need to specify one of MYSQL_ROOT_PASSWORD, MYSQL_ALLOW_EMPTY_PASSWORD and MYSQL_RANDOM_ROOT_PASSWORD'
                        exit 1
                fi
		mkdir -p "$DATADIR"
		chown -R mysql:mysql "$DATADIR"

		echo 'Running mysql_install_db'
		mysql_install_db --user=mysql --datadir="$DATADIR" --rpm
		echo 'Finished mysql_install_db'

		mysqld --user=mysql --datadir="$DATADIR" --skip-networking &
		pid="$!"

		sleep 10

		mysql=( mysql --protocol=socket -uroot )

		for i in $(seq 30 0); do
			if echo 'SELECT 1' | "${mysql[@]}" &> /dev/null; then
				break
			fi
			echo 'MySQL init process in progress...'
			sleep 1
		done
		if [ "$i" = 0 ]; then
			echo >&2 'MySQL init process failed.'
			exit 1
		fi

		# sed is for https://bugs.mysql.com/bug.php?id=20545
		mysql_tzinfo_to_sql /usr/share/zoneinfo | sed 's/Local time zone must be set--see zic manual page/FCTY/' | "${mysql[@]}" mysql
		if [ ! -z "$MYSQL_RANDOM_ROOT_PASSWORD" ]; then
			MYSQL_ROOT_PASSWORD="$(pwmake 128)"
			echo "GENERATED ROOT PASSWORD: $MYSQL_ROOT_PASSWORD"
		fi
		"${mysql[@]}" <<-EOSQL
			-- What's done in this file shouldn't be replicated
			--  or products like mysql-fabric won't work
			SET @@SESSION.SQL_LOG_BIN=0;
			DELETE FROM mysql.user ;
			CREATE USER 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}' ;
			GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION ;
			CREATE USER 'xtrabackup'@'localhost' IDENTIFIED BY '$XTRABACKUP_PASSWORD';
			GRANT RELOAD,LOCK TABLES,REPLICATION CLIENT ON *.* TO 'xtrabackup'@'localhost';
			GRANT REPLICATION CLIENT ON *.* TO monitor@'%' IDENTIFIED BY 'monitor';
			DROP DATABASE IF EXISTS test ;
			FLUSH PRIVILEGES ;
		EOSQL
		if [ ! -z "$MYSQL_ROOT_PASSWORD" ]; then
			mysql+=( -p"${MYSQL_ROOT_PASSWORD}" )
		fi

		if [ "$MYSQL_DATABASE" ]; then
			echo "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\` ;" | "${mysql[@]}"
			mysql+=( "$MYSQL_DATABASE" )
		fi

		if [ "$MYSQL_USER" -a "$MYSQL_PASSWORD" ]; then
			echo "CREATE USER '"$MYSQL_USER"'@'%' IDENTIFIED BY '"$MYSQL_PASSWORD"' ;" | "${mysql[@]}"

			if [ "$MYSQL_DATABASE" ]; then
				echo "GRANT ALL ON \`"$MYSQL_DATABASE"\`.* TO '"$MYSQL_USER"'@'%' ;" | "${mysql[@]}"
			fi

			echo 'FLUSH PRIVILEGES ;' | "${mysql[@]}"
		fi

		if [ ! -z "$MYSQL_ONETIME_PASSWORD" ]; then
			"${mysql[@]}" <<-EOSQL
				ALTER USER 'root'@'%' PASSWORD EXPIRE;
			EOSQL
		fi
		if ! kill -s TERM "$pid" || ! wait "$pid"; then
			echo >&2 'MySQL init process failed.'
			exit 1
		fi

		echo
		echo 'MySQL init process done. Ready for start up.'
		echo
	fi
	chown -R mysql:mysql "$DATADIR"

function join { local IFS="$1"; shift; echo "$*"; }

if [ -z "$DISCOVERY_SERVICE" ]; then
	cluster_join=$CLUSTER_JOIN
else
	echo
	echo '>> Registering in the discovery service'

	etcd_hosts=$(echo $DISCOVERY_SERVICE | tr ',' ' ')
	flag=1

	echo
	# Loop to find a healthy etcd host
	for i in $etcd_hosts
	do
		echo ">> Connecting to http://${i}/health"
		curl -s http://${i}/health || continue
		if curl -s http://$i/health | jq -e 'contains({ "health": "true"})'; then
			healthy_etcd=$i
			flag=0
			break
		else
			echo >&2 ">> Node $i is unhealty. Proceed to the next node."
		fi
	done

	# Flag is 0 if there is a healthy etcd host
	if [ $flag -ne 0 ]; then
		echo ">> Couldn't reach healthy etcd nodes."
		exit 1
	fi

	echo
	echo ">> Selected healthy etcd: $healthy_etcd"

  if [ ! -z "$healthy_etcd" ]; then
    URL="http://$healthy_etcd/v2/keys/galera/$CLUSTER_NAME"

    set +e
    echo >&2 ">> Waiting for $TTL seconds to read non-expired keys.."
    sleep $TTL

    # Read the list of registered IP addresses
    echo >&2 ">> Retrieving list of keys for $CLUSTER_NAME"
    addr=$(curl -s $URL | jq -r '.node.nodes[]?.key' | awk -F'/' '{print $(NF)}')
    cluster_join=$(join , $addr)

    ipaddr=$(hostname -i | awk {'print $1'})
    [ -z $ipaddr ] && ipaddr=$(hostname -I | awk {'print $1'})

    echo
    if [ -z $cluster_join ]; then
      echo >&2 ">> KV store is empty. This is a the first node to come up."
      echo
      echo >&2 ">> Registering $ipaddr in http://$healthy_etcd"
      curl -s $URL/$ipaddr/ipaddress -X PUT -d "value=$ipaddr"
    else
      curl -s ${URL}?recursive=true\&sorted=true > /tmp/out
      running_nodes=$(cat /tmp/out | jq -r '.node.nodes[].nodes[]? | select(.key | contains ("wsrep_local_state_comment")) | select(.value == "Synced") | .key' | awk -F'/' '{print $(NF-1)}' | tr "\n" ' '| sed -e 's/[[:space:]]*$//')
      echo
      echo ">> Running nodes: [${running_nodes}]"

      if [ -z "$running_nodes" ]; then
        # if there is no Synced node, determine the sequence number.
        TMP=/var/lib/mysql/$(hostname).err
        echo >&2 ">> There is no node in synced state."
        echo >&2 ">> It's unsafe to bootstrap unless the sequence number is the latest."
        echo >&2 ">> Determining the Galera last committed seqno using --wsrep-recover.."
        echo

        mysqld_safe --wsrep-cluster-address=gcomm:// --wsrep-recover
        cat $TMP
        seqno=$(cat $TMP | tr ' ' "\n" | grep -e '[a-z0-9]*-[a-z0-9]*:[0-9]' | head -1 | cut -d ":" -f 2)
        # if this is a new container, set seqno to 0
        if [ $INITIALIZED -eq 1 ]; then
		echo >&2 ">> This is a new container, thus setting seqno to 0."
		seqno=0
	fi

        echo
        if [ ! -z $seqno ]; then
          echo >&2 ">> Reporting seqno:$seqno to ${healthy_etcd}."
          WAIT=$(($TTL * 2))
          curl -s $URL/$ipaddr/seqno -X PUT -d "value=$seqno&ttl=$WAIT"
        else
          seqno=$(cat $TMP | tr ' ' "\n" | grep -e '[a-z0-9]*-[a-z0-9]*:[0-9]' | head -1)
          echo >&2 ">> Unable to determine Galera sequence number."
          exit 1
        fi
        rm $TMP

        echo
        echo >&2 ">> Sleeping for $TTL seconds to wait for other nodes to report."
        sleep $TTL

        echo
        echo >&2 ">> Retrieving list of seqno for $CLUSTER_NAME"
        bootstrap_flag=1

        # Retrieve seqno from etcd
        curl -s ${URL}?recursive=true\&sorted=true > /tmp/out
        cluster_seqno=$(cat /tmp/out | jq -r '.node.nodes[].nodes[]? | select(.key | contains ("seqno")) | .value' | tr "\n" ' '| sed -e 's/[[:space:]]*$//')

        for i in $cluster_seqno; do
          if [ $i -gt $seqno ]; then
            bootstrap_flag=0
            echo >&2 ">> Found another node holding a greater seqno ($i/$seqno)"
          fi
        done

        echo
        if [ $bootstrap_flag -eq 1 ]; then
          # Find the earliest node to report if there is no higher seqno
          # node_to_bootstrap=$(cat /tmp/out | jq -c '.node.nodes[].nodes[]?' | grep seqno | tr ',:\"' ' ' | sort -k 11 | head -1 | awk -F'/' '{print $(NF-1)}')
	  ## The earliest node to report if there is no higher seqno is computed wrongly: issue #6
	  node_to_bootstrap=$(cat /tmp/out | jq -c '.node.nodes[].nodes[]?' | grep seqno | tr ',:"' ' ' | sort -k5,5r -k11 | head -1 | awk -F'/' '{print $(NF-1)}')
          if [ "$node_to_bootstrap" == "$ipaddr" ]; then
            echo >&2 ">> This node is safe to bootstrap."
            cluster_join=
          else
            echo >&2 ">> Based on timestamp, $node_to_bootstrap is the chosen node to bootstrap."
            echo >&2 ">> Wait again for $TTL seconds to look for a bootstrapped node."
            sleep $TTL
            curl -s ${URL}?recursive=true\&sorted=true > /tmp/out

            # Look for a synced node again
            running_nodes2=$(cat /tmp/out | jq -r '.node.nodes[].nodes[]? | select(.key | contains ("wsrep_local_state_comment")) | select(.value == "Synced") | .key' | awk -F'/' '{print $(NF-1)}' | tr "\n" ' '| sed -e 's/[[:space:]]*$//')

            echo
            echo >&2 ">> Running nodes: [${running_nodes2}]"

            if [ ! -z "$running_nodes2" ]; then
              cluster_join=$(join , $running_nodes2)
            else
              echo
              echo >&2 ">> Unable to find a bootstrapped node to join."
              echo >&2 ">> Exiting."
              exit 1
            fi
          fi
        else
          echo >&2 ">> Refusing to start for now because there is a node holding higher seqno."
          echo >&2 ">> Wait again for $TTL seconds to look for a bootstrapped node."
          sleep $TTL

          # Look for a synced node again
          curl -s ${URL}?recursive=true\&sorted=true > /tmp/out
          running_nodes3=$(cat /tmp/out | jq -r '.node.nodes[].nodes[]? | select(.key | contains ("wsrep_local_state_comment")) | select(.value == "Synced") | .key' | awk -F'/' '{print $(NF-1)}' | tr "\n" ' '| sed -e 's/[[:space:]]*$//')

          echo
          echo >&2 ">> Running nodes: [${running_nodes3}]"

          if [ ! -z "$running_nodes2" ]; then
            cluster_join=$(join , $running_nodes3)
          else
            echo
            echo >&2 ">> Unable to find a bootstrapped node to join."
            echo >&2 ">> Exiting."
            exit 1
          fi
        fi
      else
        # if there is a Synced node, join the address
        cluster_join=$(join , $running_nodes)
      fi
    fi
    set -e

    echo
    echo >&2 ">> Cluster address is gcomm://$cluster_join"
  else
    echo
    echo >&2 '>> No healthy etcd host detected. Refused to start.'
    exit 1
  fi
fi

echo
echo >&2 ">> Starting reporting script in the background"
nohup /report_status.sh root $MYSQL_ROOT_PASSWORD $CLUSTER_NAME $TTL $DISCOVERY_SERVICE &

# set IP address based on the primary interface
sed -i "s|WSREP_NODE_ADDRESS|$ipaddr|g" /etc/my.cnf
sed -i "s|XTRABACKUP_PASSWORD|$XTRABACKUP_PASSWORD|g" /etc/my.cnf

echo
echo >&2 ">> Starting mysqld process"
if [ -z $cluster_join ]; then
	export _WSREP_NEW_CLUSTER='--wsrep-new-cluster'
	# set safe_to_bootstrap = 1
	GRASTATE=$DATADIR/grastate.dat
	[ -f $GRASTATE ] && sed -i "s|safe_to_bootstrap.*|safe_to_bootstrap: 1|g" $GRASTATE
else
	export _WSREP_NEW_CLUSTER=''
fi

# give mysqld some time to start, signal that we have finished executing this script and actual liveness checking can commence
bash -c "sleep 3; rm /entrypoint.executing"&

exec mysqld --wsrep_cluster_name=$CLUSTER_NAME --wsrep-cluster-address="gcomm://$cluster_join" --wsrep_sst_auth="xtrabackup:$XTRABACKUP_PASSWORD" $_WSREP_NEW_CLUSTER $CMDARG
