#!/bin/bash
#
# This file is subject to the terms and conditions of the GNU General Public
# License v.3.  See the file "LICENSE" in the main directory of this archive
# for more details.
#
#
# Author: Adam Leszczynski, aleszczynski@bersler.com
# Version: 1.0, 01.12.2017
# Home page: https://www.bersler.com/blog/nagios-script-for-checking-sap-replication-server-sybase-rs/
# 
# Script for monitoring SAP (Sybase) Replication Server using Nagios
#
# 
# Script performs the following checks:
# - no processes are down (suspended)
# - health status
#
# The script requires a local installation of Open Client ($SYBASE path and isql binary).
#
# default values
SERVER=
LOGIN=
PASSWORD=
CHARACTERSET=cp1250
SYBASE=/opt/sybase

while getopts "S:U:P:c:?" opt; do
  case $opt in
    S)
	  SERVER=$OPTARG
      ;;
    U)
	  LOGIN=$OPTARG
      ;;
    P)
	  PASSWORD=$OPTARG
      ;;
    C)
	  CHARACTERSET=$OPTARG
      ;;
    X)
	  SYBASE=$OPTARG
      ;;
    \?)
	  echo "ERROR, use: check_sybase_rs.sh -S server -U login [-P password]  [-C character set] [-X path_to_sybase_installation]"
	  exit
      ;;
  esac
done

if [ -z $SERVER ]; then
	echo "ERROR: -S missing"
	exit
fi
if [ -z $LOGIN ]; then
	echo "ERROR: -U missing"
	exit
fi

if [ ! -x $SYBASE/SYBASE.sh ]; then
	echo "ERROR: Missing file: $SYBASE/SYBASE.sh"
	exit
fi

source $SYBASE/SYBASE.sh
unset LANG

#test connect
out=`isql -U$LOGIN -S$SERVER -w500 -J$CHARACTERSET << EOF | tail -n +4
$PASSWORD
admin version
go
EOF`
alive=`echo "$out" | grep "Replication Server"`
if [ -z "$alive" ]; then
	echo "REPLICATION SERVER CRITICAL - Unable to connnect|threads=0 down=0"
	exit
fi;

#test health
out=`isql -U$LOGIN -S$SERVER -w500 -J$CHARACTERSET << EOF | tail -n +4
$PASSWORD
admin health
go
EOF`
healthy=`echo "$out" | grep "HEALTHY"`

#test threads
numthreads=`isql -U$LOGIN -S$SERVER -w500 -J$CHARACTERSET << EOF | tail -n +4 | wc -l
$PASSWORD
admin who
go
EOF`

#test connections down
out=`isql -U$LOGIN -S$SERVER -w500 -J$CHARACTERSET << EOF | tail -n +4
$PASSWORD
admin who_is_down
go
EOF`
connectionsdown=""
numconsdown=0
IFS=$'\n'
for a in $out; do
	#echo "-> [$a]";
	suspended=`echo "$a" | awk '{ print $NF }'`
	if [ "$connectionsdown" == "" ]; then
		connectionsdown=$suspended
	else
		connectionsdown="$connectionsdown, $suspended"
	fi;
	numconsdown=$((numconsdown+1))
done;

if [ ! -z "$healthy" ]; then
	echo "REPLICATION SERVER OK |threads=$numthreads down=0"
else
	echo "REPLICATION SERVER CRITICAL - $numconsdown threads down: $connectionsdown |threads=$numthreads down=$numconsdown"
fi;
#echo [$out]
