#!/bin/bash
find /usr/sap/[A-Z][A-Z0-9][A-Z0-9]/J${1}/j2ee/configtool/ -regex ".*/batchconfig\.[c]*sh$" -type f -exec '{}' -task get.versions.of.deployed.units \;
