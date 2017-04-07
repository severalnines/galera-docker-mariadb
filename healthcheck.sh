#!/bin/bash
# This script checks if a database container is healthy based on cluster type.
# The purpose of this script is to make Docker capable of monitoring different
# database cluster type properly.
# This script will just return exit 0 (OK) or 1 (NOT OK).

MYSQL_HOST="localhost"
MYSQL_PORT="3306"
MYSQL_USERNAME='root'
MYSQL_PASSWORD=$MYSQL_ROOT_PASSWORD
MYSQL_OPTS="-N -q -A --connect-timeout=10"
TMP_FILE="/dev/shm/mysqlchk.$$.out"
ERR_FILE="/dev/shm/mysqlchk.$$.err"
FORCE_FAIL="/dev/shm/proxyoff"
MYSQL_BIN='/usr/bin/mysql'
CHECK_QUERY="show global status where variable_name='wsrep_local_state'"
CHECK_QUERY2="show global variables where variable_name='wsrep_sst_method'"
CHECK_QUERY3="show global variables where variable_name='read_only'"
preflight_check()
{
    for I in "$TMP_FILE" "$ERR_FILE"; do
        if [ -f "$I" ]; then
            if [ ! -w $I ]; then
                echo -e "HTTP/1.1 503 Service Unavailable\r\n"
                echo -e "Content-Type: Content-Type: text/plain\r\n"
                echo -e "\r\n"
                echo -e "Cannot write to $I\r\n"
                echo -e "\r\n"
                exit 1
            fi
        fi
    done
}
return_ok()
{
    exit 0
}
return_fail()
{
    exit 1
}
preflight_check
if [ -f "$FORCE_FAIL" ]; then
        echo "$FORCE_FAIL found" > $ERR_FILE
        return_fail;
fi
status=$($MYSQL_BIN $MYSQL_OPTS --host=$MYSQL_HOST --port=$MYSQL_PORT --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD -e "$CHECK_QUERY;" 2>/dev/null | awk '{print $2;}')
if [ $? -ne 0 ]; then
        return_fail;
fi

if [ $status -eq 2 ] || [ $status -eq 4 ] ; then

    readonly=$($MYSQL_BIN $MYSQL_OPTS --host=$MYSQL_HOST --port=$MYSQL_PORT --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD -e "$CHECK_QUERY3;" 2>/dev/null | awk '{print $2;}')
    if [ $? -ne 0 ]; then
        return_fail;
    fi    
    if [ "$readonly" = "YES" -o "$readonly" = "ON" ]; then
        return_fail;
    fi

    if [ $status -eq 2 ]; then
        method=$($MYSQL_BIN $MYSQL_OPTS --host=$MYSQL_HOST --port=$MYSQL_PORT --user=$MYSQL_USERNAME --password=$MYSQL_PASSWORD -e "$CHECK_QUERY2;" 2>/dev/null | awk '{print $2;}')
        if [ $? -ne 0 ]; then
            return_fail;
        fi
        if [ -z "$method" ] || [ "$method" = "rsync" ] || [ "$method" = "mysqldump" ]; then
            return_fail;
        fi
    fi
    return_ok;
fi

return_fail;


