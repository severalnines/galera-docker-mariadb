#!/bin/bash

if [[ -f /entrypoint.executing ]]; then
  exit 0
fi

STATE_QUERY="SHOW GLOBAL STATUS WHERE variable_name='wsrep_local_state_comment'"

READINESS=0
LIVENESS=0

# Kubernetes' readiness & liveness flag
if [[ ! -z $1 ]]; then
	[[ $1 == "--readiness" ]] && READINESS=1
	[[ $1 == "--liveness" ]] && LIVENESS=1
else
  LIVENESS=1
fi

# state == Initialized --> fail all checks
# state == Synced --> succeed all checks
# anything else: alive, but not ready

# explanation of state variable:
# see http://galeracluster.com/documentation-webpages/monitoringthecluster.html
# "When the node is part of the Primary Component, the typical return values are Joining, Waiting on SST, Joined, Synced or Donor. In the event that the node is part of a nonoperational component, the return value is Initialized."
# "If the node returns any value other than the one listed here, the state comment is momentary and transient. Check the status variable again for an update."

state=$(mysql --skip-column-names --quick --no-auto-rehash --connect-timeout=10 --protocol=socket --user=root --password="$MYSQL_ROOT_PASSWORD" -e "$STATE_QUERY;" 2>/dev/null | awk '{print $2;}')
if [[ $? != 0 || -z "$state" ]]; then
  echo "1 -- command failed or state empty: $state"
  exit 1
fi
if [[ "$state" == "Initialized" ]]; then
  echo "1 -- $state"
  exit 1
fi
if [[ "$state" == "Synced" ]]; then
  echo "0 -- $state"
  exit 0
fi
echo $READINESS
exit $READINESS
