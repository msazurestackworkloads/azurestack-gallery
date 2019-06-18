#!/bin/bash

#source ./common.sh

# Handle named parameters
while [[ "$#" -gt 0 ]]
do
    case $1 in
        -o|--output-folder)
            OUTPUT_FOLDER="$2"
            shift 2
        ;;
        -s|--scripts-folder)
            SCRIPTS_FOLDER="$2"
            shift 2
        ;;
        *)
            echo ""
            log_level -e "[ERR] Incorrect option $1"
            exit 1
        ;;
    esac
done

if [[ ! -d $OUTPUT_FOLDER ]];
then
    log_level -e "output directory does not exist"
    exit 1
fi

if [[ ! -d $SCRIPTS_FOLDER ]];
then
    log_level -e "scripts folder does not exist"
    exit 1
fi

source $SCRIPTS_FOLDER/common.sh $OUTPUT_FOLDER "detecterror"

log_level -i "-----------------------------------------------------------------------------"
log_level -i "Script Parameters"
log_level -i "-----------------------------------------------------------------------------"
log_level -i "OUTPUT_FOLDER: $OUTPUT_FOLDER"
log_level -i "SCRIPTS_FOLDER: $SCRIPTS_FOLDER"
log_level -i "-----------------------------------------------------------------------------"



LOG_DIRS=$(ls ./$OUTPUT_FOLDER)

log_level -i "Log directories $LOG_DIRS"

for DIR in $LOG_DIRS
do
    if [[ -d ./$OUTPUT_FOLDER/$DIR ]]; then
        
        if [[ $DIR == "vmd"* ]]; then
            log_level -i "Checking DVM for errors"
            find_cse_errors $OUTPUT_FOLDER/$DIR/azure/cluster-provision.log
            find_cse_errors $OUTPUT_FOLDER/$DIR/cloud-init-output.log
            find_spn_errors $OUTPUT_FOLDER/$DIR/azure/deploy-script-dvm.log
        else
            log_level -i "Checking node [$DIR] for errors"
            find_cse_errors $OUTPUT_FOLDER/$DIR/azure/cluster-provision.log
            find_cse_errors $OUTPUT_FOLDER/$DIR/cloud-init-output.log
            find_etcd_bad_cert_errors $OUTPUT_FOLDER/$DIR/azure/cluster-provision.log $OUTPUT_FOLDER/$DIR/azure/etcd-status.log
        fi
    fi
done
