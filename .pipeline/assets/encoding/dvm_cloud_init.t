#cloud-config

write_files:
- path: "/opt/azure/containers/script.sh"
  permissions: "0744"
  encoding: gzip
  owner: "root"
  content: !!binary |
    SCRIPT_PLACEHOLDER