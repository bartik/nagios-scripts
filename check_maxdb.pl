#!/usr/bin/perl -w
############################## check_maxdb ##############
# Version : 0.50
# Author  : Mark Rittinghaus (rittinghaus.mark@lumberg.com)
# Licence : GPL - http://www.fsf.org/licenses/gpl.txt
#################################################################
#
# Help : ./check_maxdb.pl -h
#

use strict;
use Getopt::Long;
use Time::Local;

#set the path for the dmcli command
#my $dbmcli = "/usr/sapdb/clients/MaxDB/bin/dbmcli";
my $dbmcli = "/sapdb/programs/bin/dbmcli";

# Nagios specific
use lib "/usr/local/nagios/libexec";
use utils qw(%ERRORS);

my $Version   = '0.5';
my $o_help    = undef;    # wan't some help ?
my $o_type    = undef;    # Check type
my $o_host    = undef;    # Database Server
my $o_dbname  = undef;    # Database
my $o_user    = undef;    # Database user
my $o_version = undef;    # print version
my $o_warn    = undef;    # warning level option
my $o_crit    = undef;    # Critical level option
my $o_hours   = undef;    # hours for backup check
my $o_perf    = undef;    # Performance data

########## functions #######
sub isnnum {    # Return true if arg is not a number
  my $num = shift;
  if ( $num =~ /^(\d+\.?\d*)|(^\.\d+)$/ ) { return 0; }
  return 1;
}

sub p_version { print "check_maxdb_data version : $Version\n"; }

# functions
sub print_usage {
  print "Usage: $0 -t <D|L|B|S> -H <host> -d <dbname> -u <user,password>  -w <warn level> -c <crit level>\n";
}

sub help {
  print "\nMaxDB checks for Nagios version ", $Version, "\n";
  print "(c)2011 to Lumberg Holding - Author: Mark Rittinghaus\n\n";
  print "You need the database manager command line interface\n";
  print "for the MaxDB database system.\n";
  print "Set the variable \$dbmcli to the path of your dbmcli program.\n\n";
  print_usage();
  print <<EOT;
-h, --help
   print this help message
-t --type=[L|D|B|S]
   type of check: L check the fill size of the Log Area
                  D check the fill size of the Data Area
                  B check the backup history for failed backups in the last x hours
                  S check Database status (online, admin, cold)
-H, --hostname=HOST
   name or IP address of database host to check
-d, --database=DBNAME
   database name
-u, --user=USER,PASSWORD
   user and password for database access
-w, --warn=INTEGER
   warning level for Log/Data Area used in percent (0 for no checks) or
   warning level for number of failed backups
-c, --crit=INTEGER
   critical level for Log/Data Area used in percent (0 for no checks) or
   critical level for number of failed backups
-b, --backup-hours=INTEGER
   check backup history for the last x hours (only needed by check type B)
-f, --perfparse
   Perfparse compatible output
-V, --version
   prints version number
EOT
}

sub check_options {
  Getopt::Long::Configure("bundling");
  GetOptions(
    'h'            => \$o_help,
    'help'         => \$o_help,
    't:s'          => \$o_type,
    'type:s'       => \$o_type,
    'H:s'          => \$o_host,
    'hostname:s'   => \$o_host,
    'd:s'          => \$o_dbname,
    'dbname:s'     => \$o_dbname,
    'u:s'          => \$o_user,
    'user:s'       => \$o_user,
    'V'            => \$o_version,
    'version'      => \$o_version,
    'c:s'          => \$o_crit,
    'critical:s'   => \$o_crit,
    'w:s'          => \$o_warn,
    'warn:s'       => \$o_warn,
    'b:s'          => \$o_hours,
    'backup-hours' => \$o_hours,
    'f'            => \$o_perf,
    'perfparse'    => \$o_perf,
  );
  if ( defined($o_help) )                                                                                                                                                             { help();      exit $ERRORS{"UNKNOWN"} }
  if ( defined($o_version) )                                                                                                                                                          { p_version(); exit $ERRORS{"UNKNOWN"} }
  if ( !defined($o_type) )                                                                                                                                                            { print "No check type defiend!\n"; print_usage(); exit $ERRORS{"UNKNOWN"} }
  if ( ( $o_type ne 'L' ) && ( $o_type ne 'l' ) && ( $o_type ne 'D' ) && ( $o_type ne 'd' ) && ( $o_type ne 'B' ) && ( $o_type ne 'b' ) && ( $o_type ne 'S' ) && ( $o_type ne 's' ) ) { print "wrong check type!\n"; print_usage(); exit $ERRORS{"UNKNOWN"} }
  if ( ( ( $o_type eq 'B' ) || ( $o_type eq 'b' ) ) && !defined($o_hours) )                                                                                                           { print "No hours for backup history check defiend!\n"; print_usage(); exit $ERRORS{"UNKNOWN"} }
  if ( ( ( $o_type eq 'B' ) || ( $o_type eq 'b' ) ) && defined($o_hours) ) {
    if ( isnnum($o_hours) ) { print "Numeric value for backup hours!\n"; print_usage(); exit $ERRORS{"UNKNOWN"} }
  }
  if ( !defined($o_host) )    # check host and filter
  { print "No host defined!\n"; print_usage(); exit $ERRORS{"UNKNOWN"} }
  if ( !defined($o_dbname) ) { print "No database defined!\n"; print_usage(); exit $ERRORS{"UNKNOWN"} }
  if ( !defined($o_user) )   { print "No user defiend!\n";     print_usage(); exit $ERRORS{"UNKNOWN"} }

  #Check Warning and crit are present
  if ( ( $o_type ne 'S' ) && ( $o_type ne 's' ) ) {
    if ( !defined($o_warn) || !defined($o_crit) ) { print "Put warning and critical values!\n"; print_usage(); exit $ERRORS{"UNKNOWN"} }

    # Get rid of % sign
    $o_warn =~ s/\%//g;
    $o_crit =~ s/\%//g;
    if ( isnnum($o_warn) || isnnum($o_crit) )        { print "Numeric value for warning or critical !\n"; print_usage(); exit $ERRORS{"UNKNOWN"} }
    if ( ( $o_crit != 0 ) && ( $o_warn > $o_crit ) ) { print "warning <= critical ! \n";                  print_usage(); exit $ERRORS{"UNKNOWN"} }
    if ( ( $o_crit > 100 ) || ( $o_warn > 100 ) )    { print "warning or critical <= 100! \n";            print_usage(); exit $ERRORS{"UNKNOWN"} }
  }
}
####### Query the database #####
sub query {

  # execute dbcli
  my $ausgabe = `$dbmcli -n $o_host -d $o_dbname -u $o_user $_[0]|grep -v OK|grep -v END|grep -v CONTINUE`;
  if ( $ausgabe =~ /^Error!/ ) {
    print $ausgabe;
    exit $ERRORS{"CRITICAL"};
  }
  return $ausgabe;
}
########## end of functions #########

########## MAIN #######
check_options();
my $ausgabe;
my $label;
my @data;                # query values
my $used_perc;           # percentage used
my $used_mb;             # used data
my $size_mb;             # maximum capacity
my $used_byte;
my $size_byte;
my $output      = "";    # Output
my $output_perf = "";    # Output performance data

# check Data Area
if ( ( $o_type eq 'd' ) || ( $o_type eq 'D' ) ) {
  $ausgabe = query("sql_execute SELECT SIZE, USED_PERM_PAGES FROM SYSDD.SERVERDB_STATS");
  my @data = split /;/, $ausgabe;
  $size_byte = ( $data[0] ) * 8 * 1024;
  $used_byte = ( $data[1] ) * 8 * 1024;
  $data[0]   = ( $data[0] * 8 ) / 1024;
  $data[1]   = ( $data[1] * 8 ) / 1024;
  $used_perc = sprintf "%.2f", 100 - ( ( $data[0] - $data[1] ) / ( $data[0] / 100 ) );
  $size_mb   = sprintf "%.0f", $data[0];
  $used_mb   = sprintf "%.0f", $data[1];

  if ( $used_perc >= $o_crit ) {
    $label = "CRITICAL";
  }
  elsif ( $used_perc >= $o_warn ) {
    $label = "WARNING";
  }
  else {
    $label = "OK";
  }
  $output = "$label: Data Area used " . $used_perc . "% (" . $used_mb . "MB/" . $size_mb . "MB)";

  # perfdata
  $output_perf = "total=" . $size_byte . " used=" . $used_byte . " percent=" . $used_perc . "%;" . $o_warn . ";" . $o_crit;

  # check Log Area
}
elsif ( ( $o_type eq 'l' ) || ( $o_type eq 'L' ) ) {
  $ausgabe = query("sql_execute SELECT LOG_PAGES, USED_LOG_PAGES, LOG_NOT_SAVED FROM SYSDD.SERVERDB_STATS");
  my @data = split /;/, $ausgabe;
  $size_byte = ( $data[0] * 8 ) * 1024;
  $used_byte = ( $data[1] * 8 ) * 1024;
  $data[0]   = ( $data[0] * 8 ) / 1024;
  $data[1]   = ( $data[1] * 8 ) / 1024;
  $used_perc = sprintf "%.2f", 100 - ( ( $data[0] - $data[1] ) / ( $data[0] / 100 ) );
  $size_mb   = sprintf "%.2f", $data[0];
  $used_mb   = sprintf "%.2f", $data[1];

  if ( $used_perc >= $o_crit ) {
    $label = "CRITICAL";
  }
  elsif ( $used_perc >= $o_warn ) {
    $label = "WARNING";

  }
  else {
    $label = "OK";
  }
  $output = "$label: Log Area used " . $used_perc . "% (" . $used_mb . "MB/" . $size_mb . "MB)";

  # perfdata
  $output_perf = "total=" . $size_byte . " used=" . $used_byte . " percent=" . $used_perc . "%;" . $o_warn . ";" . $o_crit;

  # check backup history on any failed backups
}
elsif ( ( $o_type eq 'b' ) || ( $o_type eq 'B' ) ) {
  query("backup_history_open");
  $ausgabe = query("backup_history_list -c LABEL,ACTION,START,RC,ERROR -I");
  my @data = split /\012/, $ausgabe;
  my $backups_failed = 0;
  foreach (@data) {
    my @backup_set = split /\|/, $_;

    # calculation of date and comparison
    my @date_time = split /\s+/, $backup_set[2];
    my ( $year, $month,  $day )    = split /-/, $date_time[0];
    my ( $hour, $minute, $second ) = split /:/, $date_time[1];
    my $now  = time - ( 3600 * $o_hours );
    my $time = timelocal( $second, $minute, $hour, $day, ( $month - 1 ), $year );
    if ( ( $now <= $time ) && ( $backup_set[3] != 0 ) ) { $backups_failed++; }
  }
  if ( $backups_failed >= $o_crit ) {
    $label = "CRITICAL";
  }
  elsif ( $backups_failed >= $o_warn ) {
    $label = "WARNING";
  }
  else {
    $label = "OK";
  }
  $output      = "$label: " . $backups_failed . " backups in the last " . $o_hours . " hours failed";
  $output_perf = "\"backups failed=\"" . $backups_failed . ";$o_warn;$o_crit"

    # check database status
}
elsif ( ( $o_type eq 's' ) || ( $o_type eq 'S' ) ) {
  $ausgabe = query("db_state");
  my @data = split /\012/, $ausgabe;
  if ( $data[1] eq "OFFLINE" ) {
    $label = "CRITICAL";
  }
  elsif ( ( $data[1] eq "COLD" ) || ( $data[1] eq "ADMIN" ) ) {
    $label = "WARNING";
  }
  elsif ( $data[1] eq "ONLINE" ) {
    $label = "OK";
  }
  else {
    exit $ERRORS{"UNKNOWN"};
  }
  $output = "$label: Database status is: " . $data[1];
}
if ( defined($o_perf) and $output_perf ne "" ) {
  print $output, " | ", $output_perf, "\n";
}
else { print $output , "\n"; }
exit $ERRORS{"$label"};
########## end of MAIN #########
