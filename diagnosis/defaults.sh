#!/bin/bash

# When RUN_HEALTH_CHECKS is set to true, it runs a health on the cluster and reports and known configuration issues
export RUN_HEALTH_CHECKS=true

# When RUN_COLLECT_CLUSTER_LOGS is set to true, it collects and downloads the various logs from the cluster
export RUN_COLLECT_CLUSTER_LOGS=true

# When RUN_COLLECT_DVM_LOGS is set to true, it connects to the Deployment Virtual Machine [DVM] and collects the various logs pretaining to cluster deployment
export RUN_COLLECT_DVM_LOGS=true

# When RUN_DETECT_ERRORS is set to true, it combs the downloaded logs for any known errors
export RUN_DETECT_ERRORS=true

# When FORCE_DOWNLOAD is set to true, it overwrites the downloaded script files 
export FORCE_DOWNLOAD=false

# JOURNALCTL_MAX_LINES determines the maximum number of lines collecte from both the head and tail of the journalctl file
export JOURNALCTL_MAX_LINES=10000