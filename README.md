# sap-nagios-scripts
Scripts for monitoring using Nagios modified to fit for reasons like:

- not every nix* has a pgrep installed
- Perl can be a ... to install on some platforms
- You won't be allowed to install random ... in serious places just to get the fancies running.

* check_sybase_ase.sh

https://www.bersler.com/blog/nagios-script-for-checking-sap-adaptive-server-enterprise-sybase-ase/

* check_oracle

https://www.monitoring-plugins.org/doc/man/check_oracle.html

* j2eegetcomponentlist2 - this time with versions too

/usr/sap/hostctrl/exe/saphostctrl -host saphostwithjavainstance -user sapadm password -function ExecuteOperation -name J2EEGetComponentList2 SAPSYSTEM=66
