#!/bin/bash

VERSION=$1

dos2unix *.sh
mkdir -p _out
tar -czf _out/diagnosis-v${VERSION}.tar.gz collectlogs.sh getkuberneteslogs.sh hosts.sh azs-collect-windows-logs.ps1
zip -q _out/diagnosis-v${VERSION}.zip collectlogs.sh getkuberneteslogs.sh hosts.sh azs-collect-windows-logs.ps1
