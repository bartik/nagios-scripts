#!/bin/bash
#
# This file is subject to the terms and conditions of the GNU General Public
# License v.3.  See the file "COPYING" in the main directory of this archive
# for more details.
#
#
# Author: Adam Leszczynski, aleszczynski@bersler.com
# Version: 1.0, 30.11.2017
# 
# Script for monitoring SAP (Sybase) Adaptive Server Enterprise (ASE) using Nagios
#
# 
# Script performs the following checks:
# - the server is up
# - no blocked processes (default threshold is 300 seconds)
# - no long running transactions (default threshold is 300 seconds)
# - log segment is not full in all databasess
# - free space in data segment for all databasess
#
#
# The script requires a local installation of Open Client ($SYBASE path and isql binary).
#
# parameters:
# maximum allowed time for blocked processes
BLOCKEDTIME=300
# maximum time for long running transactions
LONGRUNTIME=300
# warning level for free space
FREESPACEPCTWARN=90
# critical level for free space
FREESPACEPCTERR=95

# default values
SERVER=
LOGIN=
PASSWORD=
CHARACTERSET=iso_1
SYBASE=/opt/sybase

# variables
NUMDATABASES=0
NUMPROCESSES=0
EXTRAINFO=""

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
	  echo "ERROR, use: check_sybase_ase.sh -S server -U login [-P password] [-C character set] [-X path_to_sybase_installation]"
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


########################################################################
#test connect
out=`isql -U$LOGIN -S$SERVER -w500 -J$CHARACTERSET << EOF | tail -n +4
$PASSWORD
set nocount on
go
select @@version
go
EOF`

alive=`echo "$out" | grep "Adaptive Server Enterprise"`
if [ -z "$alive" ]; then
	echo "ASE SERVER CRITICAL - Unable to connnect|databases=$NUMDATABASES processes=$NUMPROCESSES"
	exit
fi;

########################################################################
#log full
out=`isql -U$LOGIN -S$SERVER -w500 -J$CHARACTERSET << EOF | tail -n +4
$PASSWORD
set nocount on
set transaction isolation level 0
go
select name, case when name = 'tempdb' or (status3 & 256) = 256 then 'tempdb' else 'user' end as dbtype
from master..sysdatabases where lct_admin("logfull", dbid) = 1
go
EOF`
logfulldbs=""
numlogfulldbs=0
IFS=$'\n'
for a in $out; do
	dbname=`echo "$a" | awk '{ print $1 }'`
	dbtype=`echo "$a" | awk '{ print $2 }'`
	
	if [ "$dbtype" == "tempdb" ]; then
		echo "ASE SERVER CRITICAL - log full in temporary db $dbname|databases=$NUMDATABASES processes=$NUMPROCESSES"
		exit
	fi
	if [ "$logfulldbs" == "" ]; then
		logfulldbs=$dbname
	else
		logfulldbs="$logfulldbs, $dbname"
	fi;
	numlogfulldbs=$((numlogfulldbs+1))
done;

if [ ! -z "$logfulldbs" ]; then
	echo "ASE SERVER CRITICAL - log full in $numlogfulldbs dbs: $logfulldbs|databases=$NUMDATABASES processes=$NUMPROCESSES"
	exit
fi;

########################################################################
#statistical information
out=`isql -U$LOGIN -S$SERVER -w500 -J$CHARACTERSET << EOF | tail -n +4
$PASSWORD
set nocount on
set transaction isolation level 0
go
declare @databases int, @processes int
select @databases = count(*) from master..sysdatabases
select @processes = count(*) from master..sysprocesses where suid > 0 and spid <> @@spid
select @databases as databases, @processes as processes
go
EOF`

NUMDATABASES=`echo "$out" | awk '{ print $1 }'`
NUMPROCESSES=`echo "$out" | awk '{ print $2 }'`

########################################################################
#blocked processes
out=`isql -U$LOGIN -S$SERVER -w500 -J$CHARACTERSET << EOF | tail -n +4
$PASSWORD
set nocount on
set transaction isolation level 0
go
select 
	spid
from master..sysprocesses 
where
	suid > 0 
and spid <> @@spid
and status = 'lock sleep'
and blocked > 0
and time_blocked > $BLOCKEDTIME
go
EOF`
blockedprocesses=""
numblockedprocesses=0
IFS=$'\n'
for a in $out; do
	processes=`echo "$a" | awk '{ print $1 }'`
	if [ "$blockedprocesses" == "" ]; then
		blockedprocesses=$processes
	else
		blockedprocesses="$blockedprocesses, $processes"
	fi;
	numblockedprocesses=$((numblockedprocesses+1))
done;

if [ ! -z "$blockedprocesses" ]; then
	echo "ASE SERVER CRITICAL - $numblockedprocesses blocked processes SPID: $blockedprocesses|databases=$NUMDATABASES processes=$NUMPROCESSES"
	exit
fi;

########################################################################
#long running transactions
out=`isql -U$LOGIN -S$SERVER -w500 -J$CHARACTERSET << EOF | tail -n +4
$PASSWORD
set nocount on
set transaction isolation level 0
go
select db_name(dbid) from master..syslogshold where name not like '%replication_truncation_point%' and datediff(ss, starttime, getdate()) >= $LONGRUNTIME
go
EOF`
longrunningtransactions=""
numlongrunningtransactions=0
IFS=$'\n'
for a in $out; do
	transactions=`echo "$a" | awk '{ print $1 }'`
	if [ "$longrunningtransactions" == "" ]; then
		longrunningtransactions=$transactions
	else
		longrunningtransactions="$longrunningtransactions, $transactions"
	fi;
	numlongrunningtransactions=$((numlongrunningtransactions+1))
done;

if [ ! -z "$databasessuspended" ]; then
	echo "ASE SERVER CRITICAL - $numlongrunningtransactions long running transactions: $longrunningtransactions |databases=$NUMDATABASES processes=$NUMPROCESSES"
	exit
fi;


########################################################################
#free space
out=`isql -U$LOGIN -S$SERVER -w500 -J$CHARACTERSET << EOF | tail -n +4
$PASSWORD
set nocount on
set transaction isolation level 0
go

select
    convert(char(20), db_name(dbid)) dbname,
    segmap,
    sum(size) / (1048576 / @@maxpagesize) allocatedMB,
    case when segmap = 4 then
        lct_admin("logsegment_freepages", dbid)
    else
        sum(curunreservedpgs(dbid, lstart, unreservedpgs))
    end / (1048576 / @@maxpagesize) as freeMB,
    case when lct_admin("logfull", dbid) = 1 and segmap & 4 = 4
        then 100
    else 
        ceiling(round(convert(numeric(15, 4), 
		(sum(convert(numeric(15, 4), size)) -
        case when segmap = 4 then
            lct_admin("logsegment_freepages", dbid)
        else
            sum(convert(numeric(15, 4), curunreservedpgs(dbid, lstart, unreservedpgs)))
        end
        ) / sum(convert(numeric(15, 4), size))), 4) * 100)
    end as freePercent
from 
    master..sysusages
where 
    dbid in 
        (select dbid from master..sysdatabases where (status3 & 8192 != 8192 or status3 is null) and status & 32 != 32 and status2 & (16 + 32) = 0) 
group by 
    dbid,
    segmap
go
EOF`

fulldb=""
numfulldb=0
IFS=$'\n'
warning=""
error=""
for a in $out; do
	dbname=`echo "$a" | awk '{ print $1 }'`
	segmap=`echo "$a" | awk '{ print $2 }'`
	allocatedmb=`echo "$a" | awk '{ print $3 }'`
	freemb=`echo "$a" | awk '{ print $4 }'`
	freepercent=`echo "$a" | awk '{ print $5 }'`

	EXTRAINFO="$EXTRAINFO ${dbname}_seg${segmap}=${freepercent}"
	if [ $freepercent -ge $FREESPACEPCTWARN ]; then
		if [ "$fulldb" == "" ]; then
			fulldb="$dbname ($freepercent% for segmap $segmap)"
		else
			fulldb="$fulldb, $dbname ($freepercent% for segmap $segmap)"
		fi;
		numfulldb=$((numfulldb+1))
		warning=1;
	fi;
	if [ $freepercent -ge $FREESPACEPCTERR ]; then
		error=1;
	fi;
done;

if [ ! -z "$fulldb" ]; then
	if [ ! -z "$error" ]; then
		echo "ASE SERVER CRITICAL - $numfulldb space: $fulldb |databases=$NUMDATABASES processes=$NUMPROCESSES ${EXTRAINFO}"
	else
		echo "ASE SERVER WARNING - $numfulldb space: $fulldb |databases=$NUMDATABASES processes=$NUMPROCESSES ${EXTRAINFO}"
	fi;
	exit
fi;


########################################################################
#all is ok
echo "ASE SERVER OK |databases=$NUMDATABASES processes=$NUMPROCESSES ${EXTRAINFO}"
