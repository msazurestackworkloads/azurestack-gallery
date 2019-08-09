#!/bin/bash

ERRFILENAME=$1

is_master_node()
{
    if [[ $HOSTNAME == k8s-master* ]]; then
        return 0
    else
        return 1
    fi
}

###
#   <summary>
#       Wrapper around the cp command that prints a nice message if the source file does not exist.
#   </summary>
#   <param name="1">Source file expected location</param>
#   <param name="2">Destination directory</param>
###
try_copy_file()
{
    if [ -f $1 ]; then
        sudo cp $1 $2/
    else
        echo "[$(date +%Y%m%d%H%M%S)][WARN][$HOSTNAME] Expected file not found: $1" | tee -a $ERRFILENAME
    fi
}

###
#   <summary>
#       Wrapper around the cp command that prints a nice message if the source directory does not exist.
#   </summary>
#   <param name="1">Source directory expected location</param>
#   <param name="2">Destination directory</param>
###
try_copy_directory()
{
    if [ -d $1 ]; then
        sudo cp -r $1 $2/
    else
        echo "[$(date +%Y%m%d%H%M%S)][WARN][$HOSTNAME] Expected directory not found: $1" | tee -a $ERRFILENAME
    fi
}

###
#   <summary>
#       Wrapper around the cp command that prints a nice message if the source directory does not exist.
#   </summary>
#   <param name="1">Source directory expected location</param>
#   <param name="2">Destination directory</param>
###
try_copy_directory_content()
{
    if [ -d $1 ]; then
        for f in $1/*
        do
            sudo cp -r $f $2/
        done
    else
        echo "[$(date +%Y%m%d%H%M%S)][WARN][$HOSTNAME] Expected directory not found: $1" | tee -a $ERRFILENAME
    fi
}

###
#   <summary>
#       Wrapper around the find command that prints a nice message if the source directory does not exist.
#   </summary>
#   <param name="1">Source directory expected location</param>
#   <param name="2">Destination file</param>
###
try_print_directory_tree()
{
    if [ -d $1 ]; then
        sudo find $1 &> $2
    else
        echo "[$(date +%Y%m%d%H%M%S)][WARN][$HOSTNAME] Expected directory not found: $1" | tee -a $ERRFILENAME
    fi
}

###
#   <summary>
#       Retires the command for specifed retry count in case of failure
#   </summary>
#   <param name="1">Retry commands</param>
#   <param name="2">Wait for specified time</param>
###
retrycmd_if_failure() { 
    retries=$1; 
    wait=$2; 
    for i in $(seq 1 $retries); do 
        ${@:3}; [ $? -eq 0  ] && break || sleep $wait; 
    done; 
    log_level -i "Command Executed $i times."; 
}
