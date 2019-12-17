#!/bin/bash

VERSION=$1

dos2unix *.sh
mkdir -p _out
tar -czf _out/registry-diagnosis-v${VERSION}.tar.gz *.sh
zip -q _out/registry-diagnosis-v${VERSION}.zip *.sh
