#!/bin/bash

echo "Do not use this script just yet"
exit 1

if [ $# -eq 0 ]; then
    echo "Pass the file to encode"
    exit 1
fi

SCRIPT=$1
OUTPUT=${SCRIPT%.sh}.b64
TEMPLATE=$(mktemp)

cat > $TEMPLATE <<EOF
[base64(concat('#cloud-config

write_files:
- path: "/opt/azure/containers/script.sh"
  permissions: "0744"
  encoding: gzip
  owner: "root"
  content: !!binary |
    SCRIPT_PLACEHOLDER'))]
EOF

dos2unix $SCRIPT

BASE64=$(cat $SCRIPT | gzip | base64 -w 0)

cat $TEMPLATE \
| sed -e "s|SCRIPT_PLACEHOLDER|$BASE64|g" \
| tr '\r' '\n' \
| awk 1 ORS='\\n' \
| sed -e 's|"|\\"|g' \
| head -c -2 \
> $OUTPUT

rm $TEMPLATE