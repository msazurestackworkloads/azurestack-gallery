#!/bin/bash

collectKubeletMetadata()
{
    KUBELET_REPOSITORY=$(docker images --format '{{.Repository}}' | grep hyperkube)
    KUBELET_TAG=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep hyperkube | cut -d ":" -f 2)
    KUBELET_VERBOSITY=$(cat /etc/systemd/system/kubelet.service | grep -e '--v=[0-9]' -oh | grep -e [0-9] -oh | head -n 1)
    KUBELET_LOG_FILE=${LOGDIRECTORY}/daemons/kubelet.log
    
    echo "== BEGIN HEADER =="               > ${KUBELET_LOG_FILE}
    echo "Type: Daemon"                     >> ${KUBELET_LOG_FILE}
    echo "TenantId: ${TENANT_ID}"           >> ${KUBELET_LOG_FILE}
    echo "Name: kubelet"                    >> ${KUBELET_LOG_FILE}
    echo "Version: ${KUBELET_TAG}"          >> ${KUBELET_LOG_FILE}
    echo "Verbosity: ${KUBELET_VERBOSITY}"  >> ${KUBELET_LOG_FILE}
    echo "Image: ${KUBELET_REPOSITORY}"     >> ${KUBELET_LOG_FILE}
    echo "== END HEADER =="                 >> ${KUBELET_LOG_FILE}
}

collectMobyMetadata()
{
    DOCKER_VERSION=$(docker version | grep -A 20 "Server:" | grep "Version:" | head -n 1 | cut -d ":" -f 2 | xargs)
    DOCKER_LOG_FILE=${LOGDIRECTORY}/daemons/docker.log

    echo "== BEGIN HEADER =="               > ${DOCKER_LOG_FILE}
    echo "Type: Daemon"                     >> ${DOCKER_LOG_FILE}
    echo "TenantId: ${TENANT_ID}"           >> ${DOCKER_LOG_FILE}
    echo "Name: docker"                     >> ${DOCKER_LOG_FILE}
    echo "Version: ${DOCKER_VERSION}"       >> ${DOCKER_LOG_FILE}
    echo "== END HEADER =="                 >> ${DOCKER_LOG_FILE}
}

collectEtcdMetadata()
{
    ETCD_VERSION=$(/usr/bin/etcd --version | grep "etcd Version:" | cut -d ":" -f 2 | xargs)
    ETCD_LOG_FILE=${LOGDIRECTORY}/daemons/etcd.log

    echo "== BEGIN HEADER =="               > ${ETCD_LOG_FILE}
    echo "Type: Daemon"                     >> ${ETCD_LOG_FILE}
    echo "TenantId: ${TENANT_ID}"           >> ${ETCD_LOG_FILE}
    echo "Name: etcd"                       >> ${ETCD_LOG_FILE}
    echo "Version: ${ETCD_VERSION}"         >> ${ETCD_LOG_FILE}
    echo "== END HEADER =="                 >> ${ETCD_LOG_FILE}
}

collectContainerMetadata()
{
    local cid=$1
    local pname=$2
    local cname=$3

    CVERBOSITY=$(docker inspect ${cid} | grep -e "--v=[0-9]" -oh | grep -e [0-9] -oh | head -n 1)
    IMAGE_SHA=$(docker inspect ${cid} | grep Image | grep -e "sha256:[[:alnum:]]*" -oh | head -n 1 | cut -d ':' -f 2)
    IMAGE=$(docker image inspect ${IMAGE_SHA} | jq -r '.[] | .RepoTags | @tsv' | xargs)
    CLOG_FILE=${LOGDIRECTORY}/containers/${pname}-${cname}.log

    echo "== BEGIN HEADER =="       > ${CLOG_FILE}
    echo "Type: Container"          >> ${CLOG_FILE}
    echo "TenantId: ${TENANT_ID}"   >> ${CLOG_FILE}
    echo "Name: ${cname}"           >> ${CLOG_FILE}
    echo "Hostname: ${HOSTNAME}"    >> ${CLOG_FILE}
    echo "ContainerID: ${cid}"      >> ${CLOG_FILE}
    echo "Image: ${IMAGE}"          >> ${CLOG_FILE}
    echo "Verbosity: ${CVERBOSITY}" >> ${CLOG_FILE}
    echo "== END HEADER =="         >> ${CLOG_FILE}
}

TMP=$(mktemp -d)
LOGDIRECTORY=${TMP}/${HOSTNAME}
mkdir -p ${LOGDIRECTORY}

LOGFILENAME="kube_logs.tar.gz"
sudo rm -f $LOGFILENAME

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Collecting /var/log/azure logs"
mkdir -p ${LOGDIRECTORY}/var/log/azure
sudo cp /var/log/azure/*.log ${LOGDIRECTORY}/var/log/azure || :
sudo cp /var/log/waagent.log ${LOGDIRECTORY}/var/log || :

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Collecting static pods manifests"
mkdir -p ${LOGDIRECTORY}/etc/kubernetes/manifests
sudo cp /etc/kubernetes/manifests/* ${LOGDIRECTORY}/etc/kubernetes/manifests 2>/dev/null

test $# -gt 0 && NAMESPACES=$@
test -z "${NAMESPACES}" && echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Collecting logs from pods in all namespaces"
test -n "${NAMESPACES}" && echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Collecting logs from pods in these namespaces: $NAMESPACES"
mkdir -p ${LOGDIRECTORY}/containers

for cid in $(docker ps -a -q --no-trunc)
do
    cns=$(docker inspect --format='{{ index .Config.Labels "io.kubernetes.pod.namespace" }}' ${cid})
    
    # if NAMESPACES not set, then collect everything
    if [ -z "${NAMESPACES}" ] || (echo $NAMESPACES | grep -qw $cns);
    then
        # Ignore the Pause container
        if docker inspect --format='{{ .Config.Image }}' ${cid} | grep -q -v pause-amd64;
        then
            pname=$(docker inspect --format='{{ index .Config.Labels "io.kubernetes.pod.name" }}' ${cid})
            cname=$(docker inspect --format='{{ index .Config.Labels "io.kubernetes.container.name" }}' ${cid})
            clog=$(docker inspect --format='{{ .LogPath }}' ${cid})

            collectContainerMetadata ${cid} ${pname} ${cname}
            sudo docker inspect ${cid} &> ${LOGDIRECTORY}/containers/${pname}-${cname}.json
            sudo cat $clog >> ${LOGDIRECTORY}/containers/${pname}-${cname}.log
        fi
    fi
done

test -n "${NAMESPACES}" && echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Collecting daemon logs"
mkdir -p ${LOGDIRECTORY}/daemons

TENANT_ID=$(sudo jq -r '.tenantId' /etc/kubernetes/azure.json)    

# TODO use --until --since --lines to limit size
if systemctl list-units | grep -q kubelet.service; then
    collectKubeletMetadata
    sudo journalctl -n 10000 --utc -o short-iso -u kubelet &>> ${LOGDIRECTORY}/daemons/kubelet.log
fi

if systemctl list-units | grep -q etcd.service; then
    collectEtcdMetadata
    sudo journalctl -n 10000 --utc -o short-iso -u etcd &>> ${LOGDIRECTORY}/daemons/etcd.log
fi

if systemctl list-units | grep -q docker.service; then
    collectMobyMetadata
    sudo journalctl -n 10000 --utc -o short-iso -u docker &>> ${LOGDIRECTORY}/daemons/docker.log
fi

sync

echo "[$(date +%Y%m%d%H%M%S)][INFO][$HOSTNAME] Compressing logs and cleaning up temp files"
CURRETUSER=$(whoami)
sudo chown -R ${CURRETUSER} ${LOGDIRECTORY}
sudo tar -czf ${LOGFILENAME} -C ${TMP} ${HOSTNAME}
sudo chown ${CURRETUSER} ${LOGFILENAME}
